import type { ServiceScope } from '@microsoft/sp-core-library'
import type { GuestRequestService, SiteService } from '../../services'
import type { IGuestRequest, IInviteSettings } from '../../models/IGuestRequest'

export interface ICurrentUser {
  loginName: string
  displayName: string
  email: string
}

export type InviteStatusDisplayMode = 'inline' | 'dialog'

export interface IInviteGuestsProps {
  title: string
  description?: string
  displayMode: InviteStatusDisplayMode
  siteUrl: string
  siteTitle: string
  currentUser: ICurrentUser
  service: GuestRequestService
  siteService: SiteService
  themeProvider: ServiceScope
}

export interface IInviteGuestsContext {
  siteUrl: string
  siteTitle: string
  currentUser: ICurrentUser
  service: GuestRequestService
  siteService: SiteService
  requests: IGuestRequest[]
  loading: boolean
  error: string | undefined
  refresh: () => Promise<void>
  invite: (emails: string[], settings: IInviteSettings) => Promise<void>
  retry: (itemId: number) => Promise<void>
}
