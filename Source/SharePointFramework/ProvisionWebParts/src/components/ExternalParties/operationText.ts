import * as strings from 'ProvisionWebPartsStrings'

import type { PartyRole } from '../../models/IExternalParties'
import type { IOperationLabel, IOperationState, OperationStatus } from '../../services/parties'
import { format } from '../../utils/format'

export const roleText = (role: PartyRole | string | undefined): string =>
  role === 'Contributor'
    ? strings.Parties.RoleContributor
    : role === 'Reader'
      ? strings.Parties.RoleReader
      : role || ''

/** Text for one step in the progress list. */
export const operationText = (label: IOperationLabel): string => {
  const target = label.target || ''
  switch (label.action) {
    case 'check':
      return strings.Parties.OpCheck
    case 'createGroup':
      return format(strings.Parties.OpCreateGroup, target)
    case 'createLibrary':
      return format(strings.Parties.OpCreateLibrary, target)
    case 'breakInheritance':
      return format(strings.Parties.OpBreakInheritance, target)
    case 'addRole':
      return format(strings.Parties.OpAddRole, target, roleText(label.role))
    case 'changeRole':
      return format(strings.Parties.OpChangeRole, target, roleText(label.role))
    case 'removeRole':
      return format(strings.Parties.OpRemoveRole, target)
    case 'ensureExternalProjectManager':
      return format(strings.Parties.OpEnsureEpl, target, label.principal || '')
    case 'addNavigationLink':
      return format(strings.Parties.OpNavigation, target)
    default:
      return target
  }
}

export const operationStatusText: Record<OperationStatus, string> = {
  pending: strings.Parties.StatusPending,
  running: strings.Parties.StatusRunning,
  done: strings.Parties.StatusDone,
  skipped: strings.Parties.StatusSkipped,
  failed: strings.Parties.StatusFailed
}

/** The error for a failed step, translated when it has a known code. */
export const operationErrorText = (state: IOperationState): string | undefined => {
  if (state.status !== 'failed') return undefined
  switch (state.errorCode) {
    case 'GroupExists':
      return format(strings.Parties.ErrorGroupExists, state.error)
    case 'LibraryUrlInUse':
      return format(strings.Parties.ErrorLibraryUrlInUse, state.error)
    case 'LibraryTitleInUse':
      return format(strings.Parties.ErrorLibraryTitleInUse, state.error)
    default:
      return state.error
  }
}
