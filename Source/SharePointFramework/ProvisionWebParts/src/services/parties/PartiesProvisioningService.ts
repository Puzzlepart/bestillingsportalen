import type { SPFI } from '@pnp/sp'
import { spPost } from '@pnp/sp'
import { body } from '@pnp/queryable'
import '@pnp/sp/webs'
import '@pnp/sp/lists'
import '@pnp/sp/items'
import '@pnp/sp/folders'
import '@pnp/sp/site-groups/web'
import '@pnp/sp/site-users/web'
import '@pnp/sp/security'
import '@pnp/sp/navigation'

import { RoleKind } from '../../models/IExternalParties'
import type { IPartiesSiteInfo } from './PartiesService'
import type { IPartiesWriter, ISecurableRef } from './partyOperations'
import { isLinklessHeading, normalizeNavUrl } from './partyNaming'

const LINKLESS_HEADING_URL = 'http://linkless.header/'

const odataString = (value: string): string => `'${value.replace(/'/g, "''")}'`

const isNotFound = (error: unknown): boolean =>
  /\[404\]|does not exist|finnes ikke|ikke funnet/i.test((error as Error)?.message || '')

interface IRawBinding {
  RoleTypeKind: number
  Hidden: boolean
}

/**
 * The SharePoint writes behind "Ny part" and "Gi tilgang". Runs with the
 * current user's own permissions (an owner), so no extra API permissions are
 * needed. Every method is safe to call again: it changes nothing that is
 * already in place. The rules follow New-Samarbeidspart.ps1 and
 * Grant-Samarbeidstilgang.ps1.
 */
export class PartiesProvisioningService implements IPartiesWriter {
  private readonly _roleDefinitionIds = new Map<RoleKind, number>()

  constructor(
    private readonly sp: SPFI,
    private readonly site: IPartiesSiteInfo
  ) {}

  public async findGroup(title: string): Promise<{ id: number; description: string } | undefined> {
    const groups = (await this.sp.web.siteGroups
      .filter(`Title eq ${odataString(title)}`)
      .select('Id', 'Description')()) as { Id: number; Description?: string }[]
    return groups[0] ? { id: groups[0].Id, description: groups[0].Description || '' } : undefined
  }

  public async createGroup(title: string, description: string): Promise<number> {
    const group = await this.sp.web.siteGroups.add({
      Title: title,
      Description: description,
      OnlyAllowMembersViewMembership: true,
      AllowMembersEditMembership: false,
      AllowRequestToJoinLeave: false
    })
    const created = this.sp.web.siteGroups.getById(group.Id)
    if (this.site.ownerGroupId) await created.setUserAsOwner(this.site.ownerGroupId)
    // SharePoint can add the creator as a member. The party group is for the party only.
    const members = (await this.sp.web.siteGroups.getById(group.Id).users.select('Id')()) as {
      Id: number
    }[]
    if (members.some((m) => m.Id === this.site.currentUserId)) {
      await this.sp.web.siteGroups.getById(group.Id).users.removeById(this.site.currentUserId)
    }
    return group.Id
  }

  public async findLibrary(
    serverRelativeUrl: string
  ): Promise<{ id: string; title: string; description: string } | undefined> {
    try {
      const list = (await this.sp.web
        .getList(serverRelativeUrl)
        .select('Id', 'Title', 'Description')()) as {
        Id: string
        Title: string
        Description?: string
      }
      return { id: list.Id, title: list.Title, description: list.Description || '' }
    } catch (e) {
      if (isNotFound(e)) return undefined
      throw e
    }
  }

  public async libraryTitleInUse(title: string, exceptUrl: string): Promise<boolean> {
    const lists = (await this.sp.web.lists
      .filter(`Title eq ${odataString(title)}`)
      .select('Id', 'RootFolder/ServerRelativeUrl')
      .expand('RootFolder')()) as { RootFolder: { ServerRelativeUrl: string } }[]
    return lists.some(
      (l) => l.RootFolder.ServerRelativeUrl.toLowerCase() !== exceptUrl.toLowerCase()
    )
  }

  public async createLibrary(urlName: string, title: string, description: string): Promise<string> {
    // The title given at creation becomes the URL. The display title is set afterwards.
    const list = await this.sp.web.lists.add(urlName, description, 101, false, {
      EnableVersioning: true
    })
    await this.sp.web.lists.getById(list.Id).update({ Title: title, Description: description })
    return list.Id
  }

  public async ensureFolders(listId: string, names: string[]): Promise<number> {
    if (!names.length) return 0
    const existing = (await this.sp.web.lists
      .getById(listId)
      .rootFolder.folders.select('Name')()) as { Name: string }[]
    const have = new Set(existing.map((f) => f.Name.toLowerCase()))
    let created = 0
    for (const name of names) {
      if (have.has(name.toLowerCase())) continue
      await this.sp.web.lists.getById(listId).rootFolder.folders.addUsingPath(name)
      created++
    }
    return created
  }

  public async hasUniqueRoleAssignments(ref: ISecurableRef): Promise<boolean> {
    const result = (await this._securable(ref).select('HasUniqueRoleAssignments')()) as {
      HasUniqueRoleAssignments: boolean
    }
    return result.HasUniqueRoleAssignments
  }

  public async breakInheritance(ref: ISecurableRef): Promise<void> {
    const userId = this.site.currentUserId
    // When the creator has direct access on the parent, it was given on purpose and is kept.
    const parentHasUser = (await this._parentAssignments(ref, userId)).length > 0
    await this._securable(ref).breakRoleInheritance(true, false)
    if (!parentHasUser && (await this.getRoleKinds(ref, userId, true)).length > 0) {
      await this._securable(ref).roleAssignments.getById(userId).delete()
    }
  }

  public async getRoleKinds(
    ref: ISecurableRef,
    principalId: number,
    includeHidden = false
  ): Promise<RoleKind[]> {
    const assignments = (await this._securable(ref)
      .roleAssignments.filter(`PrincipalId eq ${principalId}`)
      .expand('RoleDefinitionBindings')
      .select(
        'PrincipalId',
        'RoleDefinitionBindings/RoleTypeKind',
        'RoleDefinitionBindings/Hidden'
      )()) as {
      RoleDefinitionBindings: IRawBinding[]
    }[]
    return assignments
      .flatMap((a) => a.RoleDefinitionBindings || [])
      .filter((b) => includeHidden || (!b.Hidden && b.RoleTypeKind !== RoleKind.Guest))
      .map((b) => b.RoleTypeKind as RoleKind)
  }

  public async addRole(ref: ISecurableRef, principalId: number, kind: RoleKind): Promise<void> {
    await this._securable(ref).roleAssignments.add(principalId, await this._roleDefinitionId(kind))
  }

  public async removePrincipal(ref: ISecurableRef, principalId: number): Promise<void> {
    await this._securable(ref).roleAssignments.getById(principalId).delete()
  }

  public async ensureNavigationLink(heading: string, title: string, url: string): Promise<boolean> {
    const nodes = (await this.sp.web.navigation.quicklaunch.select('Id', 'Title', 'Url')()) as {
      Id: number
      Title: string
      Url: string
    }[]
    let headingId = nodes.find(
      (n) =>
        n.Title.trim().toLowerCase() === heading.trim().toLowerCase() && isLinklessHeading(n.Url)
    )?.Id
    if (headingId === undefined) {
      // PnPjs add() cannot set IsExternal, which a heading without a link needs.
      const created = await spPost<{ Id: number }>(
        this.sp.web.navigation.quicklaunch,
        body({ Title: heading, Url: LINKLESS_HEADING_URL, IsExternal: true, IsVisible: true })
      )
      headingId = created.Id
    }
    const children = (await this.sp.web.navigation.quicklaunch
      .getById(headingId)
      .children.select('Url')()) as { Url: string }[]
    const wanted = normalizeNavUrl(url)
    if (children.some((c) => normalizeNavUrl(c.Url) === wanted)) return false
    await this.sp.web.navigation.quicklaunch.getById(headingId).children.add(title, url, true)
    return true
  }

  private _securable(ref: ISecurableRef) {
    if (ref.web) return this.sp.web
    const list = this.sp.web.lists.getById(ref.listId)
    return ref.itemId ? list.items.getById(ref.itemId) : list
  }

  /** Role assignments for the principal on the parent scope the object would copy from. */
  private _parentAssignments(ref: ISecurableRef, principalId: number): Promise<unknown[]> {
    const parent = ref.itemId ? this.sp.web.lists.getById(ref.listId) : this.sp.web
    return parent.roleAssignments.filter(`PrincipalId eq ${principalId}`).select('PrincipalId')()
  }

  private async _roleDefinitionId(kind: RoleKind): Promise<number> {
    if (!this._roleDefinitionIds.has(kind)) {
      const def = (await this.sp.web.roleDefinitions
        .getByType(kind as number as 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7)
        .select('Id')()) as {
        Id: number
      }
      this._roleDefinitionIds.set(kind, def.Id)
    }
    return this._roleDefinitionIds.get(kind)
  }
}
