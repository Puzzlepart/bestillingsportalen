import type { SPFI } from '@pnp/sp';
import type { IGuestRequest, INewGuestRequest, GuestRequestStatus } from '../models/IGuestRequest';

const SELECT = [
  'Id',
  'Title',
  'SiteUrl',
  'SiteTitle',
  'Status',
  'GuestId',
  'InviteRedeemUrl',
  'ErrorMessage',
  'Created',
  'Modified',
  'RequestedBy/Id',
  'RequestedBy/Title',
  'RequestedBy/EMail'
];
const EXPAND = ['RequestedBy'];

export class GuestRequestService {
  constructor(private readonly sp: SPFI, private readonly listTitle: string) {}

  public async getForSite(siteUrl: string): Promise<IGuestRequest[]> {
    return (await this.sp.web.lists
      .getByTitle(this.listTitle)
      .items.select(...SELECT)
      .expand(...EXPAND)
      .filter(`SiteUrl/Url eq '${siteUrl.replace(/'/g, "''")}'`)
      .orderBy('Created', false)
      .top(500)()) as IGuestRequest[];
  }

  public async createMany(emails: string[], siteUrl: string, siteTitle: string): Promise<IGuestRequest[]> {
    const list = this.sp.web.lists.getByTitle(this.listTitle);
    const results: IGuestRequest[] = [];
    for (const email of emails) {
      const payload: INewGuestRequest = {
        Title: email,
        SiteUrl: { Url: siteUrl, Description: siteTitle },
        SiteTitle: siteTitle,
        Status: 'Pending'
      };
      const add = await list.items.add(payload);
      const itemId = (add as { data?: { Id: number } }).data?.Id ?? (add as unknown as { Id: number }).Id;
      const created = (await list.items.getById(itemId).select(...SELECT).expand(...EXPAND)()) as IGuestRequest;
      results.push(created);
    }
    return results;
  }

  public async retry(itemId: number): Promise<void> {
    await this.sp.web.lists.getByTitle(this.listTitle).items.getById(itemId).update({
      Status: 'Pending' as GuestRequestStatus,
      ErrorMessage: ''
    });
  }
}
