import type { SPFI } from '@pnp/sp'

export type UserAccessLevel = 'Owner' | 'Member' | 'Other'

export interface ISiteGroup {
  Id: number
  Title: string
  LoginName: string
  Description?: string
  PrincipalType?: number
}

export interface ISiteContext {
  isGroupConnected: boolean
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
    const [site, visitorGroup] = await Promise.all([
      this.sp.site.select('GroupId')() as Promise<{ GroupId?: string }>,
      this.sp.web.associatedVisitorGroup
        .select('Id', 'Title')()
        .then((g) => g as { Id: number; Title: string })
        .catch(() => undefined)
    ])
    const isGroupConnected =
      !!site.GroupId && site.GroupId !== '00000000-0000-0000-0000-000000000000'
    return {
      isGroupConnected,
      groupId: isGroupConnected ? site.GroupId : undefined,
      associatedVisitorGroupId: visitorGroup?.Id,
      associatedVisitorGroupTitle: visitorGroup?.Title
    }
  }

  public async getSiteGroups(): Promise<ISiteGroup[]> {
    const groups = (await this.sp.web.siteGroups
      .select('Id', 'Title', 'LoginName', 'Description', 'PrincipalType')
      .filter('PrincipalType eq 8')
      .top(500)()) as ISiteGroup[]
    return groups.sort((a, b) => a.Title.localeCompare(b.Title))
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
