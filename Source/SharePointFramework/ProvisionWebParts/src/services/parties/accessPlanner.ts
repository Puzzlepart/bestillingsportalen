import {
  type IAccessSnapshot,
  type IAccessTarget,
  type PartyRole,
  RoleKind
} from '../../models/IExternalParties'
import { accessForPrincipal, effectiveAssignments, partyRoleToKind } from './accessModel'

/** One SharePoint operation needed to reach the desired access. */
export type AccessStep =
  | { type: 'breakInheritance'; target: IAccessTarget }
  | { type: 'add'; target: IAccessTarget; role: PartyRole }
  | { type: 'change'; target: IAccessTarget; from: RoleKind; role: PartyRole }
  | { type: 'remove'; target: IAccessTarget }
  | { type: 'ensureExternalProjectManager'; target: IAccessTarget }

export type AccessChangeKind = 'add' | 'change' | 'remove'

export interface IAccessChange {
  kind: AccessChangeKind
  target: IAccessTarget
  role?: PartyRole
  from?: RoleKind
  /** True when inheritance is broken (with copy) before the party is added. */
  breaksInheritance: boolean
}

export interface IAccessPlan {
  changes: IAccessChange[]
  steps: AccessStep[]
  /** Keys of targets that were requested but cannot be shared (protected or unknown). */
  rejected: string[]
}

export interface IPlanAccessInput {
  snapshot: IAccessSnapshot
  partyId: number
  /** Group id of the external project manager, if the group exists. */
  externalProjectManagerId?: number
  /**
   * The access the party should have after saving, per target key. A target
   * that is missing or undefined means no access.
   */
  desired: Record<string, PartyRole | undefined>
}

/**
 * Compares the party's access today with the desired access and returns the
 * changes and the SharePoint steps to get there. Pure: reads nothing and
 * changes nothing. Follows the rules in Grant-Samarbeidstilgang.ps1:
 *
 * - Protected libraries (and anything not in the snapshot) are rejected.
 * - A target that inherits gets inheritance broken with copy first, so owners,
 *   members and the external project manager keep their access.
 * - When the party is added to a target where the external project manager
 *   has no access after the break, the external project manager gets Read.
 * - Changing a role adds the new role and removes the old one.
 * - Removing access removes only the party's role assignment. Inheritance is
 *   not restored, because others may have been given access there.
 */
export const planAccessChanges = (input: IPlanAccessInput): IAccessPlan => {
  const { snapshot, partyId, externalProjectManagerId, desired } = input
  const current = new Map<string, RoleKind>()
  for (const a of accessForPrincipal(snapshot, partyId)) current.set(a.target.key, a.role)

  const targetByKey = new Map(snapshot.targets.map((t) => [t.key, t]))
  const changes: IAccessChange[] = []
  const steps: AccessStep[] = []
  const rejected: string[] = []

  // Keep the order of the snapshot so libraries come before their folders.
  const keys = snapshot.targets
    .map((t) => t.key)
    .filter((k) => current.has(k) || desired[k] !== undefined)
  for (const key of Object.keys(desired)) {
    if (desired[key] !== undefined && !targetByKey.has(key)) rejected.push(key)
  }

  for (const key of keys) {
    const target = targetByKey.get(key)
    const want = desired[key]
    const have = current.get(key)

    if (want === undefined) {
      if (have !== undefined) {
        changes.push({ kind: 'remove', target, from: have, breaksInheritance: false })
        steps.push({ type: 'remove', target })
      }
      continue
    }

    if (target.isProtected) {
      rejected.push(key)
      continue
    }

    if (have === undefined) {
      const breaksInheritance = !target.hasUniqueRoleAssignments
      if (breaksInheritance) steps.push({ type: 'breakInheritance', target })
      steps.push({ type: 'add', target, role: want })
      const assignmentsAfter = effectiveAssignments(snapshot, target)
      if (
        externalProjectManagerId !== undefined &&
        !assignmentsAfter.some((a) => a.principalId === externalProjectManagerId)
      ) {
        steps.push({ type: 'ensureExternalProjectManager', target })
      }
      changes.push({ kind: 'add', target, role: want, breaksInheritance })
      continue
    }

    if (have !== partyRoleToKind(want)) {
      changes.push({ kind: 'change', target, role: want, from: have, breaksInheritance: false })
      steps.push({ type: 'change', target, from: have, role: want })
    }
  }

  return { changes, steps, rejected }
}

/** The party's access today as a desired-access map, the starting point for editing. */
export const currentDesiredAccess = (
  snapshot: IAccessSnapshot,
  partyId: number
): Record<string, PartyRole | undefined> => {
  const result: Record<string, PartyRole | undefined> = {}
  for (const a of accessForPrincipal(snapshot, partyId)) {
    if (a.role === RoleKind.Contributor || a.role === RoleKind.Reader) {
      result[a.target.key] = a.role === RoleKind.Contributor ? 'Contributor' : 'Reader'
    } else {
      // Stronger roles (e.g. Edit) are shown as Contributor and kept unless changed.
      result[a.target.key] = 'Contributor'
    }
  }
  return result
}
