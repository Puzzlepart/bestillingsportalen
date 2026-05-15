import * as React from 'react'
import { Badge, mergeClasses } from '@fluentui/react-components'
import { PersonRegular } from '@fluentui/react-icons'

import * as strings from 'ProvisionWebPartsStrings'
import styles from './M365GroupRoleSection.module.scss'

interface IM365GroupRoleSectionProps {
  isGroupConnected: boolean
}

export const M365GroupRoleSection: React.FC<IM365GroupRoleSectionProps> = ({
  isGroupConnected
}) => {
  if (!isGroupConnected) {
    return (
      <section className={mergeClasses(styles.section, styles.sectionDisabled)}>
        <h4 className={styles.title}>{strings.M365GroupSectionTitle}</h4>
        <p className={styles.description}>
          <strong>{strings.M365GroupNotConnectedTitle}.</strong>{' '}
          {strings.M365GroupNotConnectedDescription}
        </p>
      </section>
    )
  }

  return (
    <section className={styles.section}>
      <h4 className={styles.title}>{strings.M365GroupSectionTitle}</h4>
      <div className={styles.roleRow}>
        <Badge appearance='tint' color='informative' icon={<PersonRegular />}>
          {strings.M365GroupRoleGuestLabel}
        </Badge>
      </div>
      <p className={styles.description}>{strings.M365GroupRoleGuestDescription}</p>
    </section>
  )
}
