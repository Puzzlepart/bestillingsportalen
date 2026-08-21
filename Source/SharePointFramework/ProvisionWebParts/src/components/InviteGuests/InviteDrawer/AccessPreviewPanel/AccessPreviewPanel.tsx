import * as React from 'react'
import { MessageBar, MessageBarBody, MessageBarTitle } from '@fluentui/react-components'

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

const computeItems = (props: IAccessPreviewProps): string[] => {
  const { role, spGroupAction, spGroupName, spPermissionLevel, isGroupConnected } = props
  const items: string[] = []

  // The requestable role is locked to Visitor/None (guests can never be
  // Member/Owner), so the preview only ever describes limited access.
  if (role === 'Visitor') {
    items.push(strings.AccessSiteRead)
    if (isGroupConnected) {
      items.push(strings.AccessNoM365)
    }
  } else {
    items.push(strings.AccessNoM365)
  }

  if ((spGroupAction === 'AddToExisting' || spGroupAction === 'Preset') && spGroupName) {
    items.push(formatTemplate(strings.AccessSpGroupAddTemplate, spGroupName))
  } else if (spGroupAction === 'CreateNew' && spGroupName && spPermissionLevel) {
    const permLabel = strings[PERMISSION_LABEL_KEYS[spPermissionLevel]] as string
    items.push(formatTemplate(strings.AccessSpGroupCreateTemplate, spGroupName, permLabel))
  }

  return items
}

export const AccessPreviewPanel: React.FC<IAccessPreviewProps> = (props) => {
  const items = computeItems(props)

  return (
    <MessageBar intent='info' className={styles.bar}>
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
