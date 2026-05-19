import type { ServiceScope } from '@microsoft/sp-core-library'
import type { GraphService, GuestRequestService, SiteService } from '../../services'
import type { FeatureToggleMode, IGuestInput, IGuestRequest } from '../../models/IGuestRequest'

export type InviteStatusDisplayMode = 'inline' | 'dialog'

export type InviteMode = 'Single' | 'Multi'

export type InviteAccessLevel = 'Owner' | 'Member' | 'Anyone'

export interface IInviteGuestsProps {
  title: string
  description?: string
  displayMode: InviteStatusDisplayMode
  inviteMode: InviteMode
  inviteAccessLevel: InviteAccessLevel
  perGuestProfileMode: FeatureToggleMode
  perGuestRoleMode: FeatureToggleMode
  siteUrl: string
  siteTitle: string
  service: GuestRequestService
  siteService: SiteService
  graphService: GraphService
  themeProvider: ServiceScope
}

export interface IInviteGuestsContext {
  siteUrl: string
  siteTitle: string
  inviteMode: InviteMode
  perGuestProfileMode: FeatureToggleMode
  perGuestRoleMode: FeatureToggleMode
  service: GuestRequestService
  siteService: SiteService
  graphService: GraphService
  requests: IGuestRequest[]
  loading: boolean
  error: string | undefined
  refresh: () => Promise<void>
  invite: (guests: IGuestInput[]) => Promise<void>
  retry: (itemId: number) => Promise<void>
}
