import * as React from 'react'
import { Badge } from '@fluentui/react-components'

import * as strings from 'ProvisionWebPartsStrings'
import styles from './InviteStatus.module.scss'
import { useInviteGuestsContext } from '../context'

const format = (template: string, value: number): string => template.replace('{0}', String(value))

export const StatusSummary: React.FC = () => {
  const ctx = useInviteGuestsContext()
  const { total, pending, failed } = React.useMemo(() => {
    const requests = ctx.requests || []
    return {
      total: requests.length,
      pending: requests.filter((r) => r.Status === 'Pending').length,
      failed: requests.filter((r) => r.Status === 'Failed').length
    }
  }, [ctx.requests])

  if (total === 0) return null

  return (
    <div className={styles.summary}>
      <Badge appearance='tint' color='informative'>
        {format(strings.StatusSummaryTotal, total)}
      </Badge>
      {pending > 0 && (
        <Badge appearance='tint' color='warning'>
          {format(strings.StatusSummaryPending, pending)}
        </Badge>
      )}
      {failed > 0 && (
        <Badge appearance='tint' color='danger'>
          {format(strings.StatusSummaryFailed, failed)}
        </Badge>
      )}
    </div>
  )
}
