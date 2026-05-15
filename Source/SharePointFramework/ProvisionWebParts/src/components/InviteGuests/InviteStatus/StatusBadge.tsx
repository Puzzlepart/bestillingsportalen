import * as React from 'react'
import { Badge, Tooltip } from '@fluentui/react-components'

import * as strings from 'ProvisionWebPartsStrings'
import type { GuestRequestStatus } from '../../../models/IGuestRequest'

interface IStatusBadgeProps {
  status: GuestRequestStatus
  errorMessage?: string
}

const COLOR_BY_STATUS: Record<GuestRequestStatus, 'warning' | 'success' | 'danger'> = {
  Pending: 'warning',
  Invited: 'success',
  Failed: 'danger'
}

const LABEL_BY_STATUS: Record<GuestRequestStatus, keyof typeof strings> = {
  Pending: 'StatusPending',
  Invited: 'StatusInvited',
  Failed: 'StatusFailed'
}

export const StatusBadge: React.FC<IStatusBadgeProps> = ({ status, errorMessage }) => {
  const badge = (
    <Badge appearance='filled' color={COLOR_BY_STATUS[status]}>
      {strings[LABEL_BY_STATUS[status]]}
    </Badge>
  )
  if (status === 'Failed' && errorMessage) {
    return (
      <Tooltip content={errorMessage} relationship='description' withArrow>
        {badge}
      </Tooltip>
    )
  }
  return badge
}
