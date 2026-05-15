export type GuestRequestStatus = 'Pending' | 'Invited' | 'Failed'

export type M365GroupRole = 'None' | 'Guest'

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
  M365GroupRole: M365GroupRole
  SPGroupAction: SPGroupAction
  SPGroupName?: string
  SPPermissionLevel?: SPPermissionLevel
  RequestedById?: number
}

export interface IInviteSettings {
  m365GroupRole: M365GroupRole
  spGroupAction: SPGroupAction
  spGroupName?: string
  spPermissionLevel?: SPPermissionLevel
}
