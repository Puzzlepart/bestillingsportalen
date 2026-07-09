import * as React from 'react'
import { Tab, TabList, type TabValue } from '@fluentui/react-components'
import { CheckmarkCircle16Regular, PersonAdd16Regular } from '@fluentui/react-icons'

import type { IGuestInput } from '../../../../models/IGuestRequest'
import styles from './GuestTabList.module.scss'

interface IGuestTabListProps {
  guests: IGuestInput[]
  activeEmail: string | undefined
  onSelect: (email: string) => void
}

export const GuestTabList: React.FC<IGuestTabListProps> = ({ guests, activeEmail, onSelect }) => {
  return (
    <TabList
      className={styles.tabList}
      selectedValue={activeEmail}
      onTabSelect={(_, data) => onSelect(data.value as string)}
      appearance='subtle'
      size='small'>
      {guests.map((g) => (
        <Tab
          key={g.email}
          value={g.email as TabValue}
          icon={g.exists ? <CheckmarkCircle16Regular /> : <PersonAdd16Regular />}>
          {g.displayName ?? g.email}
        </Tab>
      ))}
    </TabList>
  )
}
