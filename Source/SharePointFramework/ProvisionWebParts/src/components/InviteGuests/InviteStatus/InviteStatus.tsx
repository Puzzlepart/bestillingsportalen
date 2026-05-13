import * as React from 'react';
import {
  DataGrid,
  DataGridBody,
  DataGridCell,
  DataGridHeader,
  DataGridHeaderCell,
  DataGridRow,
  Spinner,
  type DataGridProps
} from '@fluentui/react-components';

import * as strings from 'ProvisionWebPartsStrings';
import styles from './InviteStatus.module.scss';
import { Commands } from './Commands';
import { useColumns } from './useColumns';
import { useInviteStatus } from './useInviteStatus';
import type { InviteStatusRow } from './types';

export const InviteStatus: React.FC = () => {
  const columns = useColumns();
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
  } = useInviteStatus();

  const onSelectionChange: DataGridProps['onSelectionChange'] = (_e, data) => {
    const next = Array.from(data.selectedItems)[0];
    setSelectedId(typeof next === 'number' ? next : undefined);
  };

  const selectedItems = React.useMemo<Set<number>>(
    () => (selectedId !== undefined ? new Set([selectedId]) : new Set()),
    [selectedId]
  );

  return (
    <section className={styles.container}>
      <h3 className={styles.heading}>{strings.StatusHeader}</h3>

      <Commands
        search={search}
        onSearchChange={setSearch}
        onRefresh={() => void onRefresh()}
        onRetry={() => void onRetry()}
        retryEnabled={retryEnabled}
        refreshing={loading}
      />

      {loading && rows.length === 0 ? (
        <div className={styles.loading}>
          <Spinner labelPosition="after" label={strings.RefreshButton} />
        </div>
      ) : rows.length === 0 ? (
        <div className={styles.empty}>{strings.StatusEmpty}</div>
      ) : (
        <div className={styles.grid}>
          <DataGrid
            items={rows}
            columns={columns}
            sortable
            selectionMode="single"
            selectedItems={selectedItems}
            onSelectionChange={onSelectionChange}
            getRowId={(item: InviteStatusRow) => item.Id}
            focusMode="composite"
            resizableColumns
          >
            <DataGridHeader>
              <DataGridRow>
                {({ renderHeaderCell }) => <DataGridHeaderCell>{renderHeaderCell()}</DataGridHeaderCell>}
              </DataGridRow>
            </DataGridHeader>
            <DataGridBody<InviteStatusRow>>
              {({ item, rowId }) => (
                <DataGridRow<InviteStatusRow> key={rowId}>
                  {({ renderCell }) => <DataGridCell>{renderCell(item)}</DataGridCell>}
                </DataGridRow>
              )}
            </DataGridBody>
          </DataGrid>
        </div>
      )}
    </section>
  );
};
