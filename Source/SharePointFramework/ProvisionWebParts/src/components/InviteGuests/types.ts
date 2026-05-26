import type { ServiceScope } from '@microsoft/sp-core-library'
import type { GraphService, GuestRequestService, SiteService } from '../../services'
import type {
  FeatureToggleMode,
  IGuestInput,
  IGuestRequest,
  M365GroupRole,
  SPGroupAction,
  SPPermissionLevel
} from '../../models/IGuestRequest'

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
  defaultM365GroupRole: M365GroupRole
  defaultSpGroupAction: SPGroupAction
  defaultSpGroupName: string
  defaultSpPermissionLevel: SPPermissionLevel
  autoSelectVisitorGroup: boolean
  lockM365GroupRole: boolean
  lockSpGroupAction: boolean
  showAccessPreview: boolean
  showStatusSummary: boolean
  showCopyRedeemUrl: boolean
  showRetryButton: boolean
  showColumnM365Role: boolean
  showColumnSPGroupAction: boolean
  showColumnSPGroupName: boolean
  showColumnSPPermissionLevel: boolean
  showM365GroupRoleSection: boolean
  showSPGroupSection: boolean
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
  defaultM365GroupRole: M365GroupRole
  defaultSpGroupAction: SPGroupAction
  defaultSpGroupName: string
  defaultSpPermissionLevel: SPPermissionLevel
  autoSelectVisitorGroup: boolean
  lockM365GroupRole: boolean
  lockSpGroupAction: boolean
  showAccessPreview: boolean
  showStatusSummary: boolean
  showCopyRedeemUrl: boolean
  showRetryButton: boolean
  showColumnM365Role: boolean
  showColumnSPGroupAction: boolean
  showColumnSPGroupName: boolean
  showColumnSPPermissionLevel: boolean
  showM365GroupRoleSection: boolean
  showSPGroupSection: boolean
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
