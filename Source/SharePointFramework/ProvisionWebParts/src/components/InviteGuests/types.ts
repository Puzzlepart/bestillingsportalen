import type { ServiceScope } from '@microsoft/sp-core-library';
import type { GuestRequestService } from '../../services/GuestRequestService';
import type { IGuestRequest } from '../../models/IGuestRequest';

export interface ICurrentUser {
  loginName: string;
  displayName: string;
  email: string;
}

export interface IInviteGuestsProps {
  title: string;
  siteUrl: string;
  siteTitle: string;
  currentUser: ICurrentUser;
  service: GuestRequestService;
  themeProvider: ServiceScope;
}

export interface IInviteGuestsContext {
  siteUrl: string;
  siteTitle: string;
  currentUser: ICurrentUser;
  service: GuestRequestService;
  requests: IGuestRequest[];
  loading: boolean;
  error: string | undefined;
  refresh: () => Promise<void>;
  invite: (emails: string[]) => Promise<void>;
  retry: (itemId: number) => Promise<void>;
}
