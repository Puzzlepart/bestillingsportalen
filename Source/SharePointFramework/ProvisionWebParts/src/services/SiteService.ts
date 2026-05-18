import type { SPFI } from '@pnp/sp'

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
    const [web, visitorGroup] = await Promise.all([
      this.sp.web.select('Id', 'GroupId')() as Promise<{ Id: string; GroupId?: string }>,
      this.sp.web.associatedVisitorGroup
        .select('Id', 'Title')()
        .then((g) => g as { Id: number; Title: string })
        .catch(() => undefined)
    ])
    const isGroupConnected = !!web.GroupId && web.GroupId !== '00000000-0000-0000-0000-000000000000'
    return {
      isGroupConnected,
      groupId: isGroupConnected ? web.GroupId : undefined,
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
}
