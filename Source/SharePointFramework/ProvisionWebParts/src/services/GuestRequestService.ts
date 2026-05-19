import type { SPFI } from '@pnp/sp'
import type { IGuestInput, IGuestRequest, INewGuestRequest } from '../models/IGuestRequest'

const SELECT = [
  'Id',
  'Title',
  'SiteUrl',
  'SiteTitle',
  'Status',
  'GuestId',
  'InviteRedeemUrl',
  'ErrorMessage',
  'FirstName',
  'LastName',
  'Company',
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
    guests: IGuestInput[],
    siteUrl: string,
    siteTitle: string
  ): Promise<IGuestRequest[]> {
    const list = this.sp.web.lists.getByTitle(this.listTitle)
    const currentUserId = (await this.sp.web.currentUser.select('Id')()).Id
    const results: IGuestRequest[] = []
    for (const guest of guests) {
      const payload: INewGuestRequest = {
        Title: guest.email,
        SiteUrl: siteUrl,
        SiteTitle: siteTitle,
        Status: 'Pending',
        FirstName: guest.firstName || undefined,
        LastName: guest.lastName || undefined,
        Company: guest.company || undefined,
        M365GroupRole: guest.m365GroupRole ?? 'None',
        SPGroupAction: guest.spGroupAction ?? 'None',
        SPGroupName: guest.spGroupName,
        SPPermissionLevel: guest.spPermissionLevel,
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

  /**
   * Re-trigger the invitation flow for a failed item. The `ProcessGuestRequest`
   * Logic App trigger only fires on NEW items (`/onnewitems`), so updating the
   * existing item's status doesn't restart the workflow. Instead, we create a
   * new list item with the same payload (which fires the trigger) and recycle
   * the old failed item.
   */
  public async retry(itemId: number): Promise<void> {
    const list = this.sp.web.lists.getByTitle(this.listTitle)
    const existing = (await list.items
      .getById(itemId)
      .select(...SELECT)
      .expand(...EXPAND)()) as IGuestRequest

    const currentUserId = (await this.sp.web.currentUser.select('Id')()).Id
    const payload: INewGuestRequest = {
      Title: existing.Title,
      SiteUrl: existing.SiteUrl,
      SiteTitle: existing.SiteTitle,
      Status: 'Pending',
      FirstName: existing.FirstName,
      LastName: existing.LastName,
      Company: existing.Company,
      M365GroupRole: existing.M365GroupRole ?? 'None',
      SPGroupAction: existing.SPGroupAction ?? 'None',
      SPGroupName: existing.SPGroupName,
      SPPermissionLevel: existing.SPPermissionLevel,
      RequestedById: currentUserId
    }

    await list.items.add(payload)
    await list.items.getById(itemId).recycle()
  }
}
