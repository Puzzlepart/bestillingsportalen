import * as React from 'react'

import {
  type IActivityLogger,
  type IOperation,
  type IOperationState,
  runOperations
} from '../../services/parties'

export interface IOperationRun {
  states: IOperationState[]
  status: 'running' | 'ok' | 'failed'
}

/** Runs operations and keeps their progress in state. Safe to close the panel while running. */
export const useOperationRun = (): {
  run?: IOperationRun
  start: (operations: IOperation[], logger?: IActivityLogger) => Promise<boolean>
  reset: () => void
} => {
  const [run, setRun] = React.useState<IOperationRun>()
  const mounted = React.useRef(true)
  React.useEffect(
    () => () => {
      mounted.current = false
    },
    []
  )

  const start = React.useCallback(async (operations: IOperation[], logger?: IActivityLogger) => {
    setRun({
      states: operations.map((o) => ({ id: o.id, label: o.label, status: 'pending' })),
      status: 'running'
    })
    const result = await runOperations(operations, {
      logger,
      onProgress: (states) => {
        if (mounted.current) setRun({ states, status: 'running' })
      }
    })
    if (mounted.current) setRun({ states: result.states, status: result.ok ? 'ok' : 'failed' })
    return result.ok
  }, [])

  const reset = React.useCallback(() => setRun(undefined), [])
  return { run, start, reset }
}
