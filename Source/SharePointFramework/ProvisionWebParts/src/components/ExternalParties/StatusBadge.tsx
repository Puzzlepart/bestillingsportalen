import * as React from 'react'
import { Badge } from '@fluentui/react-components'
import { Checkmark12Regular } from '@fluentui/react-icons'
import * as strings from 'ProvisionWebPartsStrings'

import type { PartyStatus } from './types'

const LABELS: Record<PartyStatus, string> = {
  OK: strings.Parties.StatusOK,
  NoMembers: strings.Parties.StatusNoMembers,
  NoAccess: strings.Parties.StatusNoAccess,
  Missing: strings.Parties.StatusMissing
}

/** Status as text, with colour as a supplement only. */
export const StatusBadge: React.FC<{ status: PartyStatus }> = ({ status }) =>
  status === 'OK' ? (
    <Badge appearance='tint' color='success' icon={<Checkmark12Regular />}>
      {LABELS[status]}
    </Badge>
  ) : (
    <Badge appearance='tint' color={status === 'Missing' ? 'warning' : 'informative'}>
      {LABELS[status]}
    </Badge>
  )
