import type { SPFI } from '@pnp/sp'
import { PermissionKind } from '@pnp/sp/security'
import '@pnp/sp/webs'
import '@pnp/sp/site-groups/web'
import '@pnp/sp/site-users/web'
import '@pnp/sp/files'

import type { IParty } from '../../models/IExternalParties'
import { parsePartyType } from './partyMarker'
import { resolveGroupPrefix, stripGroupPrefix } from './partyConfig'

export interface IPartiesSiteInfo {
  title: string
  absoluteUrl: string
  serverRelativeUrl: string
  ownerGroupId?: number
  ownerGroupTitle?: string
  currentUserId: number
  currentUserLoginName: string
}

interface IRawGroup {
  Id: number
  Title: string
  Description?: string
}

/**
 * Reads the parties on the project site. A party is a SharePoint group with
 * the party marker in its description. The external project manager group is
 * found by its title (group prefix + configured name).
 */
export class PartiesService {
  constructor(private readonly sp: SPFI) {}

  /**
   * True when the current user can manage permissions and lists on the site,
   * which in practice means an owner. The web part only runs for owners.
   */
  public async currentUserCanManage(): Promise<boolean> {
    const [permissions, lists] = await Promise.all([
      this.sp.web.currentUserHasPermissions(PermissionKind.ManagePermissions),
      this.sp.web.currentUserHasPermissions(PermissionKind.ManageLists)
    ])
    return permissions && lists
  }

  public async getSiteInfo(): Promise<IPartiesSiteInfo> {
    const [web, owner, user] = await Promise.all([
      this.sp.web.select('Title', 'Url', 'ServerRelativeUrl')() as Promise<{
        Title: string
        Url: string
        ServerRelativeUrl: string
      }>,
      this.sp.web.associatedOwnerGroup
        .select('Id', 'Title')()
        .then((g) => g as { Id: number; Title: string })
        .catch((): undefined => undefined),
      this.sp.web.currentUser.select('Id', 'LoginName')() as Promise<{
        Id: number
        LoginName: string
      }>
    ])
    return {
      title: web.Title,
      absoluteUrl: web.Url,
      serverRelativeUrl: web.ServerRelativeUrl,
      ownerGroupId: owner?.Id,
      ownerGroupTitle: owner?.Title,
      currentUserId: user.Id,
      currentUserLoginName: user.LoginName
    }
  }

  /**
   * Returns the external project manager group (first) and all parties,
   * sorted by name. Member counts are read per group.
   */
  public async getParties(
    siteTitle: string,
    groupPrefix: string,
    externalProjectManager: string
  ): Promise<IParty[]> {
    const groups = (await this.sp.web.siteGroups
      .select('Id', 'Title', 'Description')
      .filter('PrincipalType eq 8')
      .top(500)()) as IRawGroup[]

    const prefix = resolveGroupPrefix(groupPrefix, siteTitle)
    // The fixed role is optional. Without a name, no group is the fixed role.
    const eplName = (externalProjectManager || '').trim()
    const eplTitle = eplName ? `${prefix}${eplName}`.toLowerCase() : undefined

    const relevant = groups
      .map((g) => {
        const isEpl = !!eplTitle && g.Title.toLowerCase() === eplTitle
        const type = parsePartyType(g.Description)
        if (!isEpl && !type) return undefined
        return {
          id: g.Id,
          title: g.Title,
          name: stripGroupPrefix(g.Title, prefix),
          type: type || '',
          memberCount: 0,
          isExternalProjectManager: isEpl
        } as IParty
      })
      .filter(Boolean)

    const counts = await Promise.all(
      relevant.map((p) =>
        this.sp.web.siteGroups
          .getById(p.id)
          .users.select('Id')()
          .then((users) => users.length)
          .catch(() => 0)
      )
    )
    relevant.forEach((p, i) => (p.memberCount = counts[i]))

    return relevant.sort((a, b) => {
      if (a.isExternalProjectManager !== b.isExternalProjectManager) {
        return a.isExternalProjectManager ? -1 : 1
      }
      return a.name.localeCompare(b.name, 'nb')
    })
  }

  /**
   * Returns the server-relative URL of a page when it exists, otherwise
   * undefined. A failed lookup counts as missing, so a link is never shown to
   * a page that is not there.
   */
  public async existingPageUrl(serverRelativeUrl: string): Promise<string | undefined> {
    if (!serverRelativeUrl) return undefined
    try {
      const exists = await this.sp.web.getFileByServerRelativePath(serverRelativeUrl).exists()
      return exists ? serverRelativeUrl : undefined
    } catch {
      return undefined
    }
  }

  /** Link to the group's members page in classic SharePoint. */
  public static groupPageUrl(siteAbsoluteUrl: string, groupId: number): string {
    return `${siteAbsoluteUrl.replace(/\/$/, '')}/_layouts/15/people.aspx?MembershipGroupId=${groupId}`
  }
}
