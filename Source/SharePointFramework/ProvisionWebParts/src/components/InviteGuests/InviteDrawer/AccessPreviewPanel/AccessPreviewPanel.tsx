import * as React from 'react'
import {
  MessageBar,
  MessageBarBody,
  MessageBarIntent,
  MessageBarTitle
} from '@fluentui/react-components'

import * as strings from 'ProvisionWebPartsStrings'
import type {
  M365GroupRole,
  SPGroupActionUI,
  SPPermissionLevel
} from '../../../../models/IGuestRequest'
import styles from './AccessPreviewPanel.module.scss'

interface IAccessPreviewProps {
  role: M365GroupRole
  spGroupAction: SPGroupActionUI
  spGroupName?: string
  spPermissionLevel?: SPPermissionLevel
  isGroupConnected: boolean
}

const PERMISSION_LABEL_KEYS: Record<SPPermissionLevel, keyof typeof strings> = {
  Read: 'SPPermissionRead',
  Contribute: 'SPPermissionContribute',
  Edit: 'SPPermissionEdit',
  'Full Control': 'SPPermissionFullControl'
}

const formatTemplate = (template: string, ...values: string[]): string =>
  values.reduce((acc, val, idx) => acc.replace(`{${idx}}`, val), template)

const computePreview = (
  props: IAccessPreviewProps
): { items: string[]; intent: MessageBarIntent } => {
  const { role, spGroupAction, spGroupName, spPermissionLevel, isGroupConnected } = props

  const spItems: string[] = []
  if ((spGroupAction === 'AddToExisting' || spGroupAction === 'Preset') && spGroupName) {
    spItems.push(formatTemplate(strings.AccessSpGroupAddTemplate, spGroupName))
  } else if (spGroupAction === 'CreateNew' && spGroupName && spPermissionLevel) {
    const permLabel = strings[PERMISSION_LABEL_KEYS[spPermissionLevel]] as string
    spItems.push(formatTemplate(strings.AccessSpGroupCreateTemplate, spGroupName, permLabel))
  }

  // The guest role ('Member') is standard M365 guest membership: the group
  // grants the team, site and group resources.
  if (role === 'Member') {
    const items = [strings.AccessSiteEdit]
    if (isGroupConnected) {
      items.push(strings.AccessTeamsMember)
      items.push(strings.AccessOneNotePlannerCalendar)
    } else {
      items.push(strings.AccessNotGroupConnectedNote)
    }
    return { items: [...items, ...spItems], intent: 'info' }
  }

  // No role AND no SP group: the invitation alone grants nothing on this site.
  // Warn so the sender makes that choice deliberately (sharing content
  // directly later is a legitimate flow).
  if (spItems.length === 0) {
    return { items: [strings.AccessNoSiteAccessWarning], intent: 'warning' }
  }
  return { items: [strings.AccessNoM365, ...spItems], intent: 'info' }
}

export const AccessPreviewPanel: React.FC<IAccessPreviewProps> = (props) => {
  const { items, intent } = computePreview(props)

  return (
    <MessageBar intent={intent} className={styles.bar}>
      <MessageBarBody>
        <MessageBarTitle>{strings.AccessPreviewTitle}</MessageBarTitle>
        <ul className={styles.list}>
          {items.map((item, idx) => (
            <li key={idx}>{item}</li>
          ))}
        </ul>
      </MessageBarBody>
    </MessageBar>
  )
}
