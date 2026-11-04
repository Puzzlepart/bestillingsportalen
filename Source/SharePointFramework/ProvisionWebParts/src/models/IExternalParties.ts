/**
 * Models for the Samarbeidsparter (external parties) web part.
 *
 * A party is a SharePoint group on the project site whose description starts
 * with the party marker (see services/parties/partyMarker.ts). Access is read
 * from SharePoint every time: libraries and first-level folders only.
 */

/** SharePoint RoleTypeKind values used by the web part. */
export enum RoleKind {
  None = 0,
  Guest = 1,
  Reader = 2,
  Contributor = 3,
  WebDesigner = 4,
  Administrator = 5,
  Editor = 6
}

/** The access levels an owner can grant a party. */
export type PartyRole = 'Contributor' | 'Reader'

export interface IPartyType {
  key: string
  label: string
  /** Title of the party's own library. `{name}` is replaced with the party name. */
  libraryTitle: string
  /** URL name of the party's own library. `{code}` is replaced with the party code. */
  libraryUrl: string
  folders: string[]
  ownLibraryRole: PartyRole
}

export interface IParty {
  id: number
  /** Full SharePoint group title, e.g. "Kaiprosjekt – Leverandør A". */
  title: string
  /** Group title without the group prefix, e.g. "Leverandør A". */
  name: string
  /** Party type label from the marker, e.g. "Leverandør". Empty for the external project manager. */
  type: string
  memberCount: number
  isExternalProjectManager: boolean
}

/** `web` is the site itself: access there applies to everything that inherits from it. */
export type AccessTargetKind = 'web' | 'library' | 'folder'

export interface IAccessTarget {
  /** Server-relative URL of the library root folder or the folder. Unique key. */
  key: string
  kind: AccessTargetKind
  listId: string
  listTitle: string
  /** Server-relative URL of the library root folder. */
  listUrl: string
  /** List item id of the folder. Only for folders. */
  itemId?: number
  /** Display name, e.g. "Dokumenter" or "Dokumenter / 01 Tegninger". */
  title: string
  /** Folder name. Only for folders. */
  name?: string
  hasUniqueRoleAssignments: boolean
  /** True for libraries in protectedLibraries and their folders. */
  isProtected: boolean
  /** Key of the parent library. Only for folders. */
  parentKey?: string
}

export interface IRoleAssignment {
  principalId: number
  principalTitle: string
  /** 8 = SharePoint group, 1 = user. */
  principalType: number
  roles: { name: string; kind: RoleKind }[]
}

export interface IAccessSnapshot {
  targets: IAccessTarget[]
  /** Role assignments per target key. Only targets with unique role assignments have entries. */
  assignments: Record<string, IRoleAssignment[]>
  /** Role assignments on the web (site level). */
  webAssignments: IRoleAssignment[]
}

/** The access a principal has on one target, from a direct role assignment. */
export interface IPrincipalAccess {
  target: IAccessTarget
  role: RoleKind
  roleName: string
}
