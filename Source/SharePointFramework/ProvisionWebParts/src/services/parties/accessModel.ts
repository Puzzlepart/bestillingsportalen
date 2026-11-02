import {
  type IAccessSnapshot,
  type IAccessTarget,
  type IPrincipalAccess,
  type IRoleAssignment,
  type PartyRole,
  RoleKind
} from '../../models/IExternalParties'

/** Order of strength between role kinds. Higher wins when a principal has several. */
const ROLE_STRENGTH: Record<number, number> = {
  [RoleKind.None]: 0,
  [RoleKind.Guest]: 1,
  [RoleKind.Reader]: 2,
  [RoleKind.Contributor]: 3,
  [RoleKind.WebDesigner]: 4,
  [RoleKind.Editor]: 5,
  [RoleKind.Administrator]: 6
}

export const partyRoleToKind = (role: PartyRole): RoleKind =>
  role === 'Contributor' ? RoleKind.Contributor : RoleKind.Reader

export const kindToPartyRole = (kind: RoleKind): PartyRole | undefined => {
  if (kind === RoleKind.Contributor) return 'Contributor'
  if (kind === RoleKind.Reader) return 'Reader'
  return undefined
}

interface IRawRoleAssignment {
  PrincipalId: number
  Member?: { Title?: string; PrincipalType?: number }
  RoleDefinitionBindings?: { Name: string; RoleTypeKind: number; Hidden?: boolean }[]
}

/**
 * Maps role assignments from the REST API to the web part model. Hidden role
 * definitions ("Limited Access") are left out, and principals with only hidden
 * roles are dropped.
 */
export const toRoleAssignments = (raw: IRawRoleAssignment[]): IRoleAssignment[] =>
  (raw || [])
    .map((ra) => ({
      principalId: ra.PrincipalId,
      principalTitle: ra.Member?.Title || '',
      principalType: ra.Member?.PrincipalType ?? 0,
      roles: (ra.RoleDefinitionBindings || [])
        .filter((rd) => !rd.Hidden && rd.RoleTypeKind !== RoleKind.Guest)
        .map((rd) => ({ name: rd.Name, kind: rd.RoleTypeKind as RoleKind }))
    }))
    .filter((ra) => ra.roles.length > 0)

/** Returns the strongest role in a list, or None. */
export const strongestRole = (roles: { kind: RoleKind; name: string }[]) =>
  roles.reduce<{ kind: RoleKind; name: string }>(
    (best, r) => (ROLE_STRENGTH[r.kind] > ROLE_STRENGTH[best.kind] ? r : best),
    { kind: RoleKind.None, name: '' }
  )

/**
 * The role assignments that apply to a target: its own if it has unique role
 * assignments, otherwise the parent library's if that has, otherwise the web's.
 */
export const effectiveAssignments = (
  snapshot: IAccessSnapshot,
  target: IAccessTarget
): IRoleAssignment[] => {
  if (target.hasUniqueRoleAssignments) return snapshot.assignments[target.key] || []
  if (target.kind === 'folder' && target.parentKey) {
    const parent = snapshot.targets.find((t) => t.key === target.parentKey)
    if (parent && parent.hasUniqueRoleAssignments) return snapshot.assignments[parent.key] || []
  }
  return snapshot.webAssignments
}

/**
 * Direct access a principal has on libraries and first-level folders with
 * unique role assignments. Targets that inherit are not listed, because the
 * access there comes from the parent.
 */
export const accessForPrincipal = (
  snapshot: IAccessSnapshot,
  principalId: number
): IPrincipalAccess[] => {
  const result: IPrincipalAccess[] = []
  for (const target of snapshot.targets) {
    if (!target.hasUniqueRoleAssignments) continue
    const ra = (snapshot.assignments[target.key] || []).find((a) => a.principalId === principalId)
    if (!ra) continue
    const best = strongestRole(ra.roles)
    if (best.kind === RoleKind.None) continue
    result.push({ target, role: best.kind, roleName: best.name })
  }
  return result
}

/** The strongest role a principal has directly on the web, or None. */
export const webRoleForPrincipal = (snapshot: IAccessSnapshot, principalId: number) => {
  const ra = snapshot.webAssignments.find((a) => a.principalId === principalId)
  return ra ? strongestRole(ra.roles) : { kind: RoleKind.None, name: '' }
}

/** Targets with unique role assignments, where the principal has no access. */
export const brokenTargetsWithoutPrincipal = (
  snapshot: IAccessSnapshot,
  principalId: number
): IAccessTarget[] =>
  snapshot.targets.filter(
    (t) =>
      t.hasUniqueRoleAssignments &&
      !(snapshot.assignments[t.key] || []).some((a) => a.principalId === principalId)
  )

export interface IAccessSummary {
  /** Libraries the principal has access to. */
  libraries: IPrincipalAccess[]
  /** First-level folders the principal has access to. */
  folders: IPrincipalAccess[]
}

export const summarizeAccess = (access: IPrincipalAccess[]): IAccessSummary => ({
  libraries: access.filter((a) => a.target.kind === 'library'),
  folders: access.filter((a) => a.target.kind === 'folder')
})
