export type GuestRequestStatus = 'Pending' | 'Invited' | 'Failed'

export type M365GroupRole = 'None' | 'Visitor' | 'Member' | 'Owner'

export type SPGroupAction = 'None' | 'AddToExisting' | 'CreateNew'

// UI-only action. 'Preset' is a fixed admin-configured group shown without a
// dropdown; it is normalized to 'AddToExisting' before persisting, so the
// stored SPGroupAction (and the list CHOICE field) only ever holds the three
// values above.
export type SPGroupActionUI = SPGroupAction | 'Preset'

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
  spGroupAction?: SPGroupActionUI
  spGroupName?: string
  spPermissionLevel?: SPPermissionLevel
}

export type FeatureToggleMode = 'Disabled' | 'Optional' | 'Enforced'
