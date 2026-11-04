import * as React from 'react'
import { Badge, Text } from '@fluentui/react-components'
import * as strings from 'ProvisionWebPartsStrings'

import { type IAccessChange, kindToPartyRole } from '../../services/parties'
import { format } from '../../utils/format'
import { roleText } from './operationText'
import styles from './ExternalParties.module.scss'

/** Text for one planned change, e.g. "Dokumenter / 01 Tegninger: Bidra." */
export const changeText = (
  change: IAccessChange,
  roleNames: Record<string, string> = {}
): string => {
  const isSite = change.target.kind === 'web'
  const title = isSite ? strings.Parties.SiteAccessLabel : change.target.title
  if (isSite) {
    return change.kind === 'remove'
      ? strings.Parties.PreviewSiteRemoveText
      : format(strings.Parties.PreviewSiteText, roleText(change.role))
  }
  switch (change.kind) {
    case 'add':
      return [
        format(strings.Parties.PreviewAddText, title, roleText(change.role)),
        change.breaksInheritance ? strings.Parties.PreviewBreaksInheritance : ''
      ]
        .filter(Boolean)
        .join(' ')
    case 'change':
      return format(
        strings.Parties.PreviewChangeText,
        title,
        roleNames[change.target.key] || roleText(kindToPartyRole(change.from)),
        roleText(change.role)
      )
    case 'remove':
      return format(strings.Parties.PreviewRemoveText, title)
  }
}

const KIND = {
  add: { text: strings.Parties.PreviewAdd, color: 'success' as const },
  change: { text: strings.Parties.PreviewChange, color: 'warning' as const },
  remove: { text: strings.Parties.PreviewRemove, color: 'danger' as const }
}

/** "Dette skjer": the planned changes in plain words, before anything is saved. */
export const AccessPreview: React.FC<{
  title: string
  changes: IAccessChange[]
  roleNames?: Record<string, string>
  empty?: string
}> = ({ title, changes, roleNames, empty }) => (
  <section className={styles.summaryBox} aria-label={title}>
    <h3 className={styles.sectionTitle}>{title}</h3>
    {changes.length === 0 ? (
      <Text>{empty ?? strings.Parties.NoChanges}</Text>
    ) : (
      <ul className={styles.previewList}>
        {changes.map((c) => (
          <li key={`${c.kind}-${c.target.key}`} className={styles.previewItem}>
            <Badge size='small' appearance='tint' color={KIND[c.kind].color}>
              {KIND[c.kind].text}
            </Badge>
            <span>{changeText(c, roleNames)}</span>
          </li>
        ))}
      </ul>
    )}
  </section>
)
