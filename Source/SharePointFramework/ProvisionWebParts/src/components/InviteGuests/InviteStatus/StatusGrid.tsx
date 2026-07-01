import * as React from 'react'
import {
  DataGrid,
  DataGridBody,
  DataGridCell,
  DataGridHeader,
  DataGridHeaderCell,
  DataGridRow,
  Spinner,
  type DataGridProps
} from '@fluentui/react-components'

import * as strings from 'ProvisionWebPartsStrings'
import styles from './InviteStatus.module.scss'
import { useInviteGuestsContext } from '../context'
import { Commands } from './Commands'
import { useColumns } from './useColumns'
import { useInviteStatus } from './useInviteStatus'
import type { InviteStatusRow } from './types'

export const StatusGrid: React.FC = () => {
  const { columns, columnSizingOptions, defaultSortState, getCellFocusMode } = useColumns()
  const { showRetryButton } = useInviteGuestsContext()
  const {
    rows,
    search,
    setSearch,
    selectedId,
    setSelectedId,
    retryEnabled,
    onRefresh,
    onRetry,
    loading
  } = useInviteStatus()

  const onSelectionChange: DataGridProps['onSelectionChange'] = (_e, data) => {
    const next = Array.from(data.selectedItems)[0]
    setSelectedId(typeof next === 'number' ? next : undefined)
  }

  const selectedItems = React.useMemo<Set<number>>(
    () => (selectedId !== undefined ? new Set([selectedId]) : new Set()),
    [selectedId]
  )

  return (
    <>
      <div className={styles.description}>{strings.StatusDialogDescription}</div>
      {loading ? (
        <Spinner
          size='extra-tiny'
          label={strings.StatusDialogSpinnerLabel}
          className={styles.gridSpinner}
        />
      ) : (
        <Commands
          search={search}
          onSearchChange={setSearch}
          onRefresh={() => void onRefresh()}
          onRetry={() => void onRetry()}
          retryEnabled={retryEnabled}
          refreshing={loading}
          showRetryButton={showRetryButton}
        />
      )}
      <div className={styles.gridScroll}>
        <DataGrid
          items={rows}
          columns={columns}
          defaultSortState={defaultSortState}
          sortable
          resizableColumns
          columnSizingOptions={columnSizingOptions}
          resizableColumnsOptions={{ autoFitColumns: false }}
          selectionMode='single'
          selectedItems={selectedItems}
          onSelectionChange={onSelectionChange}
          getRowId={(item: InviteStatusRow) => item.Id}>
          <DataGridHeader>
            <DataGridRow>
              {({ renderHeaderCell }) => (
                <DataGridHeaderCell>{renderHeaderCell()}</DataGridHeaderCell>
              )}
            </DataGridRow>
          </DataGridHeader>
          {rows.length === 0 ? (
            <div className={styles.message}>
              {search.trim()
                ? strings.StatusDialogNoSearchResultsLabel
                : strings.StatusDialogNoResultsLabel}
            </div>
          ) : (
            <DataGridBody<InviteStatusRow>>
              {({ item, rowId }) => (
                <DataGridRow<InviteStatusRow> key={rowId}>
                  {({ renderCell, columnId }) => (
                    <DataGridCell focusMode={getCellFocusMode(columnId)}>
                      {renderCell(item)}
                    </DataGridCell>
                  )}
                </DataGridRow>
              )}
            </DataGridBody>
          )}
        </DataGrid>
      </div>
    </>
  )
}
