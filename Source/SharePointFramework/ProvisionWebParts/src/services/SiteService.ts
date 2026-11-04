import type { SPFI } from '@pnp/sp'

export type UserAccessLevel = 'Owner' | 'Member' | 'Other'

export interface ISiteGroup {
  Id: number
  Title: string
  LoginName: string
  Description?: string
  PrincipalType?: number
  PermissionLevel?: string
}

// System-managed groups SharePoint auto-creates that admins should never assign
// guests to. Filtered out of the SP group dropdown.
const SYSTEM_GROUP_PREFIXES = ['Limited Access System Group', 'SharingLinks']

export interface IRoleBinding {
  Name: string
  Hidden?: boolean
  RoleTypeKind?: number
}

/** RoleTypeKind of «Limited Access» / «Begrenset tilgang». */
const ROLE_TYPE_GUEST = 1

/**
 * The permission levels to show for a group, e.g. «Lese». Limited Access is
 * the implicit grant SharePoint adds when a principal has permissions on a
 * child item, so it says nothing at group level. It is recognised by type and
 * the Hidden flag, not by name, because the name is localised («Begrenset
 * tilgang» on Norwegian sites).
 */
export const groupPermissionNames = (bindings: IRoleBinding[]): string =>
  (bindings || [])
    .filter((b) => !b.Hidden && b.RoleTypeKind !== ROLE_TYPE_GUEST && b.Name !== 'Limited Access')
    .map((b) => b.Name)
    .join(', ')

export interface ISiteContext {
  isGroupConnected: boolean
  /** Title of the site, used to show group names without the site prefix. */
  webTitle?: string
  groupId?: string
  associatedVisitorGroupId?: number
  associatedVisitorGroupTitle?: string
}

/**
 * Queries the SharePoint site where guests will be granted access — i.e. the
 * site the InviteGuests web part is hosted on, NOT the admin site holding the
 * Guest Requests list. Provides metadata the InviteDrawer needs to render the
 * M365 group + SP group sections (existing groups, group-connected detection).
 */
export class SiteService {
  constructor(private readonly sp: SPFI) {}

  public async getSiteContext(): Promise<ISiteContext> {
    // GroupId lives on the Site object (not Web). Selecting it from web returns
    // undefined silently — has bitten us before in the AddGuestToSite runbook.
    const [site, visitorGroup, web] = await Promise.all([
      this.sp.site.select('GroupId')() as Promise<{ GroupId?: string }>,
      this.sp.web.associatedVisitorGroup
        .select('Id', 'Title')()
        .then((g) => g as { Id: number; Title: string })
        .catch(() => undefined),
      this.sp.web
        .select('Title')()
        .then((w) => w as { Title: string })
        .catch((): undefined => undefined)
    ])
    const isGroupConnected =
      !!site.GroupId && site.GroupId !== '00000000-0000-0000-0000-000000000000'
    return {
      isGroupConnected,
      webTitle: web?.Title,
      groupId: isGroupConnected ? site.GroupId : undefined,
      associatedVisitorGroupId: visitorGroup?.Id,
      associatedVisitorGroupTitle: visitorGroup?.Title
    }
  }

  public async getSiteGroups(
    hiddenTerms: string[] = [],
    allowedTerms: string[] = []
  ): Promise<ISiteGroup[]> {
    const [groups, roleAssignments] = await Promise.all([
      this.sp.web.siteGroups
        .select('Id', 'Title', 'LoginName', 'Description', 'PrincipalType')
        .filter('PrincipalType eq 8')
        .top(500)() as Promise<ISiteGroup[]>,
      this.sp.web.roleAssignments
        .expand('RoleDefinitionBindings')
        .select(
          'PrincipalId',
          'RoleDefinitionBindings/Name',
          'RoleDefinitionBindings/Hidden',
          'RoleDefinitionBindings/RoleTypeKind'
        )
        .top(500)() as Promise<{ PrincipalId: number; RoleDefinitionBindings: IRoleBinding[] }[]>
    ])
    const permissionsByPrincipalId = new Map<number, string>()
    for (const ra of roleAssignments) {
      const names = groupPermissionNames(ra.RoleDefinitionBindings)
      if (names) permissionsByPrincipalId.set(ra.PrincipalId, names)
    }
    // Admin-configured allow/hidden terms: a group matches a term when its title
    // contains the term (partial, case-insensitive) or its permission level
    // equals one (exact, case-insensitive). The allowlist is an inverse filter
    // with empty-means-all: when no allowed terms are set every group passes.
    const normalizedAllowed = allowedTerms.map((t) => t.trim().toLowerCase()).filter(Boolean)
    const isAllowed = (g: ISiteGroup): boolean => {
      if (normalizedAllowed.length === 0) return true
      const title = g.Title.toLowerCase()
      const permission = (g.PermissionLevel ?? '').toLowerCase()
      return normalizedAllowed.some((term) => title.includes(term) || permission === term)
    }
    const normalizedHidden = hiddenTerms.map((t) => t.trim().toLowerCase()).filter(Boolean)
    const isHidden = (g: ISiteGroup): boolean => {
      if (normalizedHidden.length === 0) return false
      const title = g.Title.toLowerCase()
      const permission = (g.PermissionLevel ?? '').toLowerCase()
      return normalizedHidden.some((term) => title.includes(term) || permission === term)
    }
    return groups
      .filter((g) => !SYSTEM_GROUP_PREFIXES.some((p) => g.Title.startsWith(p)))
      .map((g) => ({ ...g, PermissionLevel: permissionsByPrincipalId.get(g.Id) }))
      .filter((g) => isAllowed(g))
      .filter((g) => !isHidden(g))
      .sort((a, b) => a.Title.localeCompare(b.Title))
  }

  /**
   * Determines current user's relationship to the site by checking membership
   * in the associated Owner and Member groups (which on M365-group-connected
   * sites are synced with the M365 group's Owners and Members respectively).
   * Site collection admins are always treated as 'Owner'.
   */
  public async getCurrentUserAccessLevel(): Promise<UserAccessLevel> {
    const [currentUser, ownerGroup, memberGroup] = await Promise.all([
      this.sp.web.currentUser.select('Id', 'IsSiteAdmin')() as Promise<{
        Id: number
        IsSiteAdmin: boolean
      }>,
      this.sp.web.associatedOwnerGroup
        .select('Id')()
        .catch(() => undefined) as Promise<{ Id: number } | undefined>,
      this.sp.web.associatedMemberGroup
        .select('Id')()
        .catch(() => undefined) as Promise<{ Id: number } | undefined>
    ])
    if (currentUser.IsSiteAdmin) return 'Owner'
    const userGroups = (await this.sp.web.currentUser.groups.select('Id')()) as { Id: number }[]
    if (ownerGroup && userGroups.some((g) => g.Id === ownerGroup.Id)) return 'Owner'
    if (memberGroup && userGroups.some((g) => g.Id === memberGroup.Id)) return 'Member'
    return 'Other'
  }
}
