export type GuestRequestStatus = 'Pending' | 'Invited' | 'Failed'

// The web part only ever invites EXTERNAL users: ProcessGuests posts to Graph
// /invitations and looks up existing users with `userType eq 'Guest'`. Entra
// does not support guests as owners of a Microsoft 365 group, and 'Member'
// would cascade Teams/Planner/mailbox access onto a guest. The requestable role
// is therefore locked to the site's Visitors group ('Visitor', labelled "Gjest"
// in the UI) or no role at all.
export type M365GroupRole = 'None' | 'Visitor'

// What the M365GroupRole CHOICE field may hold. Items written before the role
// lock can still carry 'Member'/'Owner', so reads stay wide (the status grid
// renders them) while writes are narrowed to M365GroupRole.
export type M365GroupRoleStored = M365GroupRole | 'Member' | 'Owner'

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
  M365GroupRole?: M365GroupRoleStored
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
