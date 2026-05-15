export type GuestRequestStatus = 'Pending' | 'Invited' | 'Failed';

export interface IGuestRequest {
  Id: number;
  Title: string;
  SiteUrl: string;
  SiteTitle: string;
  Status: GuestRequestStatus;
  GuestId?: string;
  InviteRedeemUrl?: string;
  ErrorMessage?: string;
  RequestedBy?: {
    Id: number;
    Title: string;
    EMail?: string;
  };
  Created: string;
  Modified: string;
}

export interface INewGuestRequest {
  Title: string;
  SiteUrl: string;
  SiteTitle: string;
  Status: GuestRequestStatus;
  RequestedById?: number;
}
