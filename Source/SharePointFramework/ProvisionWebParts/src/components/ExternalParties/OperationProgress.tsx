import * as React from 'react'
import { Spinner, Text } from '@fluentui/react-components'
import {
  CheckmarkCircle20Filled,
  Circle20Regular,
  DismissCircle20Filled,
  CheckmarkCircle20Regular
} from '@fluentui/react-icons'

import type { IOperationState } from '../../services/parties'
import { operationErrorText, operationStatusText, operationText } from './operationText'
import styles from './ExternalParties.module.scss'

const StatusIcon: React.FC<{ state: IOperationState }> = ({ state }) => {
  switch (state.status) {
    case 'running':
      return <Spinner size='extra-tiny' />
    case 'done':
      return <CheckmarkCircle20Filled className={styles.iconDone} />
    case 'skipped':
      return <CheckmarkCircle20Regular className={styles.iconSkipped} />
    case 'failed':
      return <DismissCircle20Filled className={styles.iconFailed} />
    default:
      return <Circle20Regular className={styles.iconPending} />
  }
}

/**
 * The steps of a run with their status. The status is given as text for
 * screen readers, and the list is a live region so progress is announced.
 */
export const OperationProgress: React.FC<{ states: IOperationState[]; label: string }> = ({
  states,
  label
}) => (
  <ol className={styles.progressList} aria-label={label} aria-live='polite'>
    {states.map((state) => {
      const error = operationErrorText(state)
      return (
        <li key={state.id} className={styles.progressItem} data-status={state.status}>
          <span className={styles.progressIcon} aria-hidden='true'>
            <StatusIcon state={state} />
          </span>
          <span>
            <Text>{operationText(state.label)}</Text>
            <span
              className={styles.visuallyHidden}>{` – ${operationStatusText[state.status]}`}</span>
            {state.status === 'skipped' && (
              <span className={styles.secondary} aria-hidden='true'>
                {operationStatusText.skipped}
              </span>
            )}
            {error && <span className={styles.progressError}>{error}</span>}
          </span>
        </li>
      )
    })}
  </ol>
)
