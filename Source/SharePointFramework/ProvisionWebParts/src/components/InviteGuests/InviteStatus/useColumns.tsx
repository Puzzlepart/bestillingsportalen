import * as React from 'react'
import { createTableColumn, type TableColumnDefinition } from '@fluentui/react-components'

import * as strings from 'ProvisionWebPartsStrings'
import { StatusBadge } from './StatusBadge'
import type { InviteStatusRow } from './types'

const formatDate = (iso: string): string => {
  if (!iso) return ''
  const d = new Date(iso)
  return d.toLocaleString()
}

export function useColumns(): TableColumnDefinition<InviteStatusRow>[] {
  return React.useMemo<TableColumnDefinition<InviteStatusRow>[]>(
    () => [
      createTableColumn<InviteStatusRow>({
        columnId: 'email',
        compare: (a, b) => a.Title.localeCompare(b.Title),
        renderHeaderCell: () => strings.ColumnEmail,
        renderCell: (item) => item.Title
      }),
      createTableColumn<InviteStatusRow>({
        columnId: 'status',
        compare: (a, b) => a.Status.localeCompare(b.Status),
        renderHeaderCell: () => strings.ColumnStatus,
        renderCell: (item) => <StatusBadge status={item.Status} errorMessage={item.ErrorMessage} />
      }),
      createTableColumn<InviteStatusRow>({
        columnId: 'requestedBy',
        compare: (a, b) => (a.RequestedBy?.Title ?? '').localeCompare(b.RequestedBy?.Title ?? ''),
        renderHeaderCell: () => strings.ColumnRequestedBy,
        renderCell: (item) => item.RequestedBy?.Title ?? ''
      }),
      createTableColumn<InviteStatusRow>({
        columnId: 'created',
        compare: (a, b) => new Date(a.Created).getTime() - new Date(b.Created).getTime(),
        renderHeaderCell: () => strings.ColumnCreated,
        renderCell: (item) => formatDate(item.Created)
      })
    ],
    []
  )
}
