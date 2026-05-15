import type { SPFI } from '@pnp/sp'
import type {
  GuestRequestStatus,
  IGuestRequest,
  IInviteSettings,
  INewGuestRequest
} from '../models/IGuestRequest'

const SELECT = [
  'Id',
  'Title',
  'SiteUrl',
  'SiteTitle',
  'Status',
  'GuestId',
  'InviteRedeemUrl',
  'ErrorMessage',
  'M365GroupRole',
  'SPGroupAction',
  'SPGroupName',
  'SPPermissionLevel',
  'Created',
  'Modified',
  'RequestedBy/Id',
  'RequestedBy/Title',
  'RequestedBy/EMail'
]
const EXPAND = ['RequestedBy']

export class GuestRequestService {
  constructor(
    private readonly sp: SPFI,
    private readonly listTitle: string
  ) {}

  public async getForSite(siteUrl: string): Promise<IGuestRequest[]> {
    return (await this.sp.web.lists
      .getByTitle(this.listTitle)
      .items.select(...SELECT)
      .expand(...EXPAND)
      .filter(`SiteUrl eq '${siteUrl.replace(/'/g, "''")}'`)
      .orderBy('Created', false)
      .top(500)()) as IGuestRequest[]
  }

  public async createMany(
    emails: string[],
    siteUrl: string,
    siteTitle: string,
    settings: IInviteSettings
  ): Promise<IGuestRequest[]> {
    const list = this.sp.web.lists.getByTitle(this.listTitle)
    const currentUserId = (await this.sp.web.currentUser.select('Id')()).Id
    const results: IGuestRequest[] = []
    for (const email of emails) {
      const payload: INewGuestRequest = {
        Title: email,
        SiteUrl: siteUrl,
        SiteTitle: siteTitle,
        Status: 'Pending',
        M365GroupRole: settings.m365GroupRole,
        SPGroupAction: settings.spGroupAction,
        SPGroupName: settings.spGroupName,
        SPPermissionLevel: settings.spPermissionLevel,
        RequestedById: currentUserId
      }
      const add = await list.items.add(payload)
      const itemId =
        (add as { data?: { Id: number } }).data?.Id ?? (add as unknown as { Id: number }).Id
      const created = (await list.items
        .getById(itemId)
        .select(...SELECT)
        .expand(...EXPAND)()) as IGuestRequest
      results.push(created)
    }
    return results
  }

  public async retry(itemId: number): Promise<void> {
    await this.sp.web.lists
      .getByTitle(this.listTitle)
      .items.getById(itemId)
      .update({
        Status: 'Pending' as GuestRequestStatus,
        ErrorMessage: ''
      })
  }
}
