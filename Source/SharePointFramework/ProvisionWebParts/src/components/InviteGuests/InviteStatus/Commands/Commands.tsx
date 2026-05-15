import * as React from 'react'
import { SearchBox, Toolbar, ToolbarButton, ToolbarDivider } from '@fluentui/react-components'
import { ArrowClockwise24Regular, ArrowSync24Regular } from '@fluentui/react-icons'

import * as strings from 'ProvisionWebPartsStrings'

interface ICommandsProps {
  search: string
  onSearchChange: (value: string) => void
  onRefresh: () => void
  onRetry: () => void
  retryEnabled: boolean
  refreshing: boolean
}

export const Commands: React.FC<ICommandsProps> = ({
  search,
  onSearchChange,
  onRefresh,
  onRetry,
  retryEnabled,
  refreshing
}) => {
  return (
    <Toolbar aria-label='Invite status commands' style={{ flexWrap: 'wrap', rowGap: 4 }}>
      <ToolbarButton
        appearance='subtle'
        icon={<ArrowClockwise24Regular />}
        onClick={onRefresh}
        disabled={refreshing}>
        {strings.RefreshButton}
      </ToolbarButton>
      <ToolbarButton
        appearance='subtle'
        icon={<ArrowSync24Regular />}
        onClick={onRetry}
        disabled={!retryEnabled}>
        {strings.RetryButton}
      </ToolbarButton>
      <ToolbarDivider />
      <SearchBox
        placeholder={strings.StatusSearchPlaceholder}
        value={search}
        onChange={(_, data) => onSearchChange(data.value)}
        style={{ minWidth: 140, flex: '1 1 140px' }}
      />
    </Toolbar>
  )
}
