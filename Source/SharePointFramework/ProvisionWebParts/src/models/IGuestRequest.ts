export type GuestRequestStatus = 'Pending' | 'Invited' | 'Failed'

// The web part only ever invites EXTERNAL users: ProcessGuests posts to Graph
// /invitations and looks up existing users with `userType eq 'Guest'`. Guests
// get access through the standard Microsoft 365 guest model: MEMBERSHIP in the
// M365 group (stored as 'Member', labelled "Gjest" in the UI), which grants the
// team, site, Planner etc. Guests can never OWN a group, so 'Owner' is not
// requestable.
export type M365GroupRole = 'None' | 'Member'

// What the M365GroupRole CHOICE field may hold. Items written before the role
// lock can also carry 'Visitor' (read access via the associated Visitors
// group — the runbook still honors it on retry) or 'Owner' (rejected), so
// reads stay wide while the UI only produces M365GroupRole.
export type M365GroupRoleStored = M365GroupRole | 'Visitor' | 'Owner'

// What may be WRITTEN back to the list: everything except 'Owner' — retrying a
// legacy 'Visitor' item must keep its read-only intent, not escalate it.
export type M365GroupRoleWritable = Exclude<M365GroupRoleStored, 'Owner'>

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
  M365GroupRole: M365GroupRoleWritable
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
