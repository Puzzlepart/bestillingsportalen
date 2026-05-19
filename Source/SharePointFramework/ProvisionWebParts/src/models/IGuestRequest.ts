export type GuestRequestStatus = 'Pending' | 'Invited' | 'Failed'

export type M365GroupRole = 'None' | 'Visitor' | 'Member' | 'Owner'

export type SPGroupAction = 'None' | 'AddToExisting' | 'CreateNew'

export type SPPermissionLevel = 'Read' | 'Contribute' | 'Edit' | 'Full Control'

export interface IGuestRequest {
  Id: number
  Title: string
  SiteUrl: string
  SiteTitle: string
  Status: GuestRequestStatus
  GuestId?: string
  InviteRedeemUrl?: string
  ErrorMessage?: string
  FirstName?: string
  LastName?: string
  Company?: string
  M365GroupRole?: M365GroupRole
  SPGroupAction?: SPGroupAction
  SPGroupName?: string
  SPPermissionLevel?: SPPermissionLevel
  RequestedBy?: {
    Id: number
    Title: string
    EMail?: string
  }
  Created: string
  Modified: string
}

export interface INewGuestRequest {
  Title: string
  SiteUrl: string
  SiteTitle: string
  Status: GuestRequestStatus
  FirstName?: string
  LastName?: string
  Company?: string
  M365GroupRole: M365GroupRole
  SPGroupAction: SPGroupAction
  SPGroupName?: string
  SPPermissionLevel?: SPPermissionLevel
  RequestedById?: number
}

export interface IGuestInput {
  email: string
  firstName: string
  lastName: string
  company: string
  exists: boolean
  loading: boolean
  /** UI-only: returned from Graph lookup and shown in GuestTabList tab label. Never persisted to the list. */
  displayName?: string
  m365GroupRole?: M365GroupRole
  spGroupAction?: SPGroupAction
  spGroupName?: string
  spPermissionLevel?: SPPermissionLevel
}

export type FeatureToggleMode = 'Disabled' | 'Optional' | 'Enforced'
