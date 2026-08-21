import * as React from 'react'
import { Radio, RadioGroup, Tooltip } from '@fluentui/react-components'
import { LockClosed16Regular } from '@fluentui/react-icons'

import * as strings from 'ProvisionWebPartsStrings'
import type { M365GroupRole } from '../../../../models/IGuestRequest'
import styles from './M365GroupRoleSection.module.scss'

interface IM365GroupRoleSectionProps {
  role: M365GroupRole
  onChange: (role: M365GroupRole) => void
  disabled?: boolean
  locked?: boolean
}

const roleLabel = (role: M365GroupRole): string =>
  role === 'Member' ? strings.M365GroupRoleMemberLabel : strings.M365GroupRoleNoneLabel

const formatLockedLabel = (template: string, value: string): string =>
  template.replace('{0}', value)

export const M365GroupRoleSection: React.FC<IM365GroupRoleSectionProps> = ({
  role,
  onChange,
  disabled,
  locked
}) => {
  return (
    <section className={styles.section}>
      <h4 className={styles.title}>{strings.M365GroupSectionTitle}</h4>
      {locked ? (
        <span className={styles.lockedValue}>
          <Tooltip content={strings.LockedFieldTooltip} relationship='label'>
            <LockClosed16Regular role='img' aria-label={strings.LockedFieldTooltip} tabIndex={0} />
          </Tooltip>
          {formatLockedLabel(strings.LockedRoleLabel, roleLabel(role))}
        </span>
      ) : (
        <RadioGroup
          value={role}
          onChange={(_, data) => onChange(data.value as M365GroupRole)}
          disabled={disabled}>
          <Radio value='None' label={strings.M365GroupRoleNoneLabel} />
          <Radio value='Member' label={strings.M365GroupRoleMemberLabel} />
        </RadioGroup>
      )}
      <p className={styles.description}>{strings.M365GroupRoleSectionDescription}</p>
    </section>
  )
}
