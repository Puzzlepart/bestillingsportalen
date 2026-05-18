import * as React from 'react'
import { Radio, RadioGroup } from '@fluentui/react-components'

import * as strings from 'ProvisionWebPartsStrings'
import type { M365GroupRole } from '../../../../models/IGuestRequest'
import styles from './M365GroupRoleSection.module.scss'

interface IM365GroupRoleSectionProps {
  role: M365GroupRole
  onChange: (role: M365GroupRole) => void
  disabled?: boolean
}

export const M365GroupRoleSection: React.FC<IM365GroupRoleSectionProps> = ({
  role,
  onChange,
  disabled
}) => {
  return (
    <section className={styles.section}>
      <h4 className={styles.title}>{strings.M365GroupSectionTitle}</h4>
      <RadioGroup
        value={role}
        onChange={(_, data) => onChange(data.value as M365GroupRole)}
        disabled={disabled}>
        <Radio value='None' label={strings.M365GroupRoleNoneLabel} />
        <Radio value='Visitor' label={strings.M365GroupRoleVisitorLabel} />
        <Radio value='Member' label={strings.M365GroupRoleMemberLabel} />
        <Radio value='Owner' label={strings.M365GroupRoleOwnerLabel} />
      </RadioGroup>
      <p className={styles.description}>{strings.M365GroupRoleSectionDescription}</p>
    </section>
  )
}
