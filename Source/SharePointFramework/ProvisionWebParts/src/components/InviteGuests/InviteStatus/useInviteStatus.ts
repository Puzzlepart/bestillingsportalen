import * as React from 'react';
import { useInviteGuestsContext } from '../context';
import type { InviteStatusRow } from './types';

interface IUseInviteStatusResult {
  rows: InviteStatusRow[];
  search: string;
  setSearch: (value: string) => void;
  selectedId: number | undefined;
  setSelectedId: (id: number | undefined) => void;
  retryEnabled: boolean;
  onRefresh: () => Promise<void>;
  onRetry: () => Promise<void>;
  loading: boolean;
}

export function useInviteStatus(): IUseInviteStatusResult {
  const ctx = useInviteGuestsContext();
  const [search, setSearch] = React.useState('');
  const [selectedId, setSelectedId] = React.useState<number | undefined>(undefined);

  const rows = React.useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return ctx.requests;
    return ctx.requests.filter((r) => r.Title.toLowerCase().includes(q));
  }, [ctx.requests, search]);

  const selectedRow = React.useMemo(
    () => (selectedId !== undefined ? ctx.requests.find((r) => r.Id === selectedId) : undefined),
    [ctx.requests, selectedId]
  );

  const retryEnabled = !!selectedRow && selectedRow.Status === 'Failed';

  const onRefresh = React.useCallback(() => ctx.refresh(), [ctx]);
  const onRetry = React.useCallback(async () => {
    if (selectedId !== undefined && retryEnabled) {
      await ctx.retry(selectedId);
      setSelectedId(undefined);
    }
  }, [ctx, selectedId, retryEnabled]);

  return {
    rows,
    search,
    setSearch,
    selectedId,
    setSelectedId,
    retryEnabled,
    onRefresh,
    onRetry,
    loading: ctx.loading
  };
}
