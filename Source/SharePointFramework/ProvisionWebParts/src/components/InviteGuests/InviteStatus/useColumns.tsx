import * as React from 'react'
import {
  Button,
  Tooltip,
  createTableColumn,
  type DataGridProps,
  type TableColumnDefinition,
  type TableColumnId,
  type TableColumnSizingOptions
} from '@fluentui/react-components'
import { Checkmark16Regular, Copy16Regular } from '@fluentui/react-icons'

import * as strings from 'ProvisionWebPartsStrings'
import { useInviteGuestsContext } from '../context'
import { StatusBadge } from './StatusBadge'
import type {
  M365GroupRoleStored,
  SPGroupAction,
  SPPermissionLevel
} from '../../../models/IGuestRequest'
import type { InviteStatusRow } from './types'

const formatDate = (iso: string): string => {
  if (!iso) return ''
  const d = new Date(iso)
  return d.toLocaleString()
}

// Takes the STORED type: rows created before the guest-role lock can still
// hold 'Member'/'Owner', and the grid must keep rendering them truthfully.
const m365RoleLabel = (role: M365GroupRoleStored | undefined): string => {
  switch (role) {
    case 'Visitor':
      return strings.M365GroupRoleVisitorLabel
    case 'Member':
      return strings.M365GroupRoleMemberLabel
    case 'Owner':
      return strings.M365GroupRoleOwnerLabel
    case 'None':
      return strings.M365GroupRoleNoneLabel
    default:
      return ''
  }
}

const spActionLabel = (action: SPGroupAction | undefined): string => {
  switch (action) {
    case 'AddToExisting':
      return strings.SPGroupActionExistingLabel
    case 'CreateNew':
      return strings.SPGroupActionNewLabel
    case 'None':
      return strings.SPGroupActionNoneLabel
    default:
      return ''
  }
}

const spPermissionLabel = (level: SPPermissionLevel | undefined): string => {
  switch (level) {
    case 'Read':
      return strings.SPPermissionRead
    case 'Contribute':
      return strings.SPPermissionContribute
    case 'Edit':
      return strings.SPPermissionEdit
    case 'Full Control':
      return strings.SPPermissionFullControl
    default:
      return ''
  }
}

const CopyRedeemUrlButton: React.FC<{ url: string }> = ({ url }) => {
  const [copied, setCopied] = React.useState(false)
  const onClick = React.useCallback(async () => {
    try {
      await navigator.clipboard.writeText(url)
      setCopied(true)
      window.setTimeout(() => setCopied(false), 2000)
    } catch {
      /* clipboard API not available in this context — silent no-op */
    }
  }, [url])
  return (
    <Tooltip
      content={copied ? strings.CopyRedeemUrlCopied : strings.CopyRedeemUrlLabel}
      relationship='label'>
      <Button
        appearance='subtle'
        size='small'
        icon={copied ? <Checkmark16Regular /> : <Copy16Regular />}
        onClick={onClick}
        aria-label={strings.CopyRedeemUrlLabel}
      />
    </Tooltip>
  )
}

export interface IUseColumnsResult {
  columns: TableColumnDefinition<InviteStatusRow>[]
  columnSizingOptions: TableColumnSizingOptions
  defaultSortState: DataGridProps['defaultSortState']
  getCellFocusMode: (columnId: TableColumnId) => 'none' | 'group' | 'cell' | undefined
}

export function useColumns(): IUseColumnsResult {
  const {
    showCopyRedeemUrl,
    showColumnM365Role,
    showColumnSPGroupAction,
    showColumnSPGroupName,
    showColumnSPPermissionLevel
  } = useInviteGuestsContext()

  return React.useMemo<IUseColumnsResult>(() => {
    const cols: TableColumnDefinition<InviteStatusRow>[] = [
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
      })
    ]

    if (showColumnM365Role) {
      cols.push(
        createTableColumn<InviteStatusRow>({
          columnId: 'm365Role',
          compare: (a, b) =>
            m365RoleLabel(a.M365GroupRole).localeCompare(m365RoleLabel(b.M365GroupRole)),
          renderHeaderCell: () => strings.ColumnM365GroupRole,
          renderCell: (item) => m365RoleLabel(item.M365GroupRole)
        })
      )
    }

    if (showColumnSPGroupAction) {
      cols.push(
        createTableColumn<InviteStatusRow>({
          columnId: 'spGroupAction',
          compare: (a, b) =>
            spActionLabel(a.SPGroupAction).localeCompare(spActionLabel(b.SPGroupAction)),
          renderHeaderCell: () => strings.ColumnSPGroupAction,
          renderCell: (item) => spActionLabel(item.SPGroupAction)
        })
      )
    }

    if (showColumnSPGroupName) {
      cols.push(
        createTableColumn<InviteStatusRow>({
          columnId: 'spGroupName',
          compare: (a, b) => (a.SPGroupName ?? '').localeCompare(b.SPGroupName ?? ''),
          renderHeaderCell: () => strings.ColumnSPGroupName,
          renderCell: (item) => item.SPGroupName ?? ''
        })
      )
    }

    if (showColumnSPPermissionLevel) {
      cols.push(
        createTableColumn<InviteStatusRow>({
          columnId: 'spPermissionLevel',
          compare: (a, b) =>
            spPermissionLabel(a.SPPermissionLevel).localeCompare(
              spPermissionLabel(b.SPPermissionLevel)
            ),
          renderHeaderCell: () => strings.ColumnSPPermissionLevel,
          renderCell: (item) => spPermissionLabel(item.SPPermissionLevel)
        })
      )
    }

    cols.push(
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
    )

    if (showCopyRedeemUrl) {
      cols.push(
        createTableColumn<InviteStatusRow>({
          columnId: 'redeemUrl',
          renderHeaderCell: () => '',
          renderCell: (item) =>
            item.Status === 'Invited' && item.InviteRedeemUrl ? (
              <CopyRedeemUrlButton url={item.InviteRedeemUrl} />
            ) : null
        })
      )
    }

    const columnSizingOptions: TableColumnSizingOptions = {
      email: { idealWidth: 242, minWidth: 198 },
      status: { idealWidth: 110, minWidth: 90 },
      m365Role: { idealWidth: 120, minWidth: 100 },
      spGroupAction: { idealWidth: 140, minWidth: 120 },
      spGroupName: { idealWidth: 160, minWidth: 120 },
      spPermissionLevel: { idealWidth: 130, minWidth: 100 },
      requestedBy: { idealWidth: 160, minWidth: 120 },
      created: { idealWidth: 160, minWidth: 130 },
      redeemUrl: { idealWidth: 50, minWidth: 40, defaultWidth: 50 }
    }

    const defaultSortState: DataGridProps['defaultSortState'] = {
      sortColumn: 'created',
      sortDirection: 'descending'
    }

    const getCellFocusMode = (columnId: TableColumnId): 'none' | 'group' | 'cell' | undefined => {
      if (columnId === 'redeemUrl') return 'group'
      return 'none'
    }

    return { columns: cols, columnSizingOptions, defaultSortState, getCellFocusMode }
  }, [
    showCopyRedeemUrl,
    showColumnM365Role,
    showColumnSPGroupAction,
    showColumnSPGroupName,
    showColumnSPPermissionLevel
  ])
}
