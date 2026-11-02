import { errorMessage } from './partyNaming'

/** What an operation did. A skipped operation found the work already done. */
export type OperationResult = 'done' | 'skipped'

export type OperationStatus = 'pending' | 'running' | 'done' | 'skipped' | 'failed'

export type OperationAction =
  | 'check'
  | 'createGroup'
  | 'createLibrary'
  | 'breakInheritance'
  | 'addRole'
  | 'changeRole'
  | 'removeRole'
  | 'ensureExternalProjectManager'
  | 'addNavigationLink'

/** Structured label, formatted by the UI so the services hold no texts. */
export interface IOperationLabel {
  action: OperationAction
  /** Display name of the group, library or folder. */
  target?: string
  role?: string
}

/** What is written to the activity log for an operation. */
export interface IOperationLogInfo {
  targetUrl?: string
  targetType?: 'Group' | 'Library' | 'Folder' | 'Navigation' | 'Site'
  principal?: string
  role?: string
}

export interface IOperation {
  id: string
  label: IOperationLabel
  log?: IOperationLogInfo
  run: () => Promise<OperationResult>
}

export interface IOperationState {
  id: string
  label: IOperationLabel
  status: OperationStatus
  error?: string
  /** Code from a PartyOperationError, for a translated message. */
  errorCode?: string
}

export interface IActivityLogEntry extends IOperationLogInfo {
  action: OperationAction
  status: 'Success' | 'Failed'
  details?: string
  correlationId: string
}

export interface IActivityLogger {
  write(entry: IActivityLogEntry): Promise<void>
}

export interface IRunOptions {
  onProgress?: (states: IOperationState[]) => void
  logger?: IActivityLogger
  correlationId?: string
}

export interface IRunResult {
  ok: boolean
  states: IOperationState[]
}

export const newCorrelationId = (): string =>
  'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16)
  })

/**
 * Runs the operations one at a time, in order, and stops at the first
 * failure. Every operation checks what exists before it changes anything, so
 * running the same list again after a failure continues where it stopped.
 * Operations that did something are written to the activity log. A failing
 * log never stops the run.
 */
export const runOperations = async (
  operations: IOperation[],
  options: IRunOptions = {}
): Promise<IRunResult> => {
  const { onProgress, logger } = options
  const correlationId = options.correlationId || newCorrelationId()
  const states: IOperationState[] = operations.map((o) => ({
    id: o.id,
    label: o.label,
    status: 'pending'
  }))
  const update = (index: number, patch: Partial<IOperationState>): void => {
    states[index] = { ...states[index], ...patch }
    onProgress?.(states.slice())
  }
  const log = async (operation: IOperation, entry: Partial<IActivityLogEntry>): Promise<void> => {
    if (!logger || !operation.log) return
    try {
      await logger.write({
        ...operation.log,
        action: operation.label.action,
        status: 'Success',
        correlationId,
        ...entry
      })
    } catch {
      // The log is for owners who look later. It never stops the work.
    }
  }

  for (let i = 0; i < operations.length; i++) {
    update(i, { status: 'running' })
    try {
      const result = await operations[i].run()
      update(i, { status: result })
      if (result === 'done') await log(operations[i], { status: 'Success' })
    } catch (e) {
      const message = errorMessage(e)
      const code = (e as { code?: unknown })?.code
      update(i, {
        status: 'failed',
        error: message,
        errorCode: typeof code === 'string' ? code : undefined
      })
      await log(operations[i], { status: 'Failed', details: message })
      return { ok: false, states }
    }
  }
  return { ok: true, states }
}
