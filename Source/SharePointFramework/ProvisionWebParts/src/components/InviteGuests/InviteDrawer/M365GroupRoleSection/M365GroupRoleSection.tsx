import * as React from 'react'
import { Badge } from '@fluentui/react-components'
import { PersonRegular } from '@fluentui/react-icons'

import * as strings from 'ProvisionWebPartsStrings'
import styles from './M365GroupRoleSection.module.scss'

export const M365GroupRoleSection: React.FC = () => {
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
