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

const computeItems = (props: IAccessPreviewProps): string[] => {
  const { role, spGroupAction, spGroupName, spPermissionLevel, isGroupConnected } = props
  const items: string[] = []

  switch (role) {
    case 'Owner':
      if (isGroupConnected) {
        items.push(strings.AccessFullAdminGroupConnected)
        items.push(strings.AccessTeamsMember)
        items.push(strings.AccessOneNotePlannerCalendar)
        items.push(strings.AccessCanInviteOthers)
      } else {
        items.push(strings.AccessFullAdminSiteOnly)
        items.push(strings.AccessNotGroupConnectedNote)
      }
      break
    case 'Member':
      items.push(strings.AccessSiteEdit)
      if (isGroupConnected) {
        items.push(strings.AccessTeamsMember)
        items.push(strings.AccessOneNotePlannerCalendar)
      } else {
        items.push(strings.AccessNotGroupConnectedNote)
      }
      break
    case 'Visitor':
      items.push(strings.AccessSiteRead)
      if (isGroupConnected) {
        items.push(strings.AccessNoM365)
      }
      break
    case 'None':
      items.push(strings.AccessNoM365)
      break
  }

  if ((spGroupAction === 'AddToExisting' || spGroupAction === 'Preset') && spGroupName) {
    items.push(formatTemplate(strings.AccessSpGroupAddTemplate, spGroupName))
  } else if (spGroupAction === 'CreateNew' && spGroupName && spPermissionLevel) {
    const permLabel = strings[PERMISSION_LABEL_KEYS[spPermissionLevel]] as string
    items.push(formatTemplate(strings.AccessSpGroupCreateTemplate, spGroupName, permLabel))
  }

  return items
}

const computeIntent = (props: IAccessPreviewProps): MessageBarIntent => {
  const { role, isGroupConnected } = props
  if (role === 'Owner') return 'warning'
  if (role === 'Member' && isGroupConnected) return 'warning'
  return 'info'
}

export const AccessPreviewPanel: React.FC<IAccessPreviewProps> = (props) => {
  const items = computeItems(props)
  const intent = computeIntent(props)
  const showWarningFooter = intent === 'warning'

  return (
    <MessageBar intent={intent} className={styles.bar}>
      <MessageBarBody>
        <MessageBarTitle>{strings.AccessPreviewTitle}</MessageBarTitle>
        <ul className={styles.list}>
          {items.map((item, idx) => (
            <li key={idx}>{item}</li>
          ))}
        </ul>
        {showWarningFooter && <p className={styles.footer}>{strings.AccessPreviewWarningFooter}</p>}
      </MessageBarBody>
    </MessageBar>
  )
}
