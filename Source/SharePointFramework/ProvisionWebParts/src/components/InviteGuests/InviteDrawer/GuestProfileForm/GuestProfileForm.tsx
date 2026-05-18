import * as React from 'react'
import { Input, MessageBar, MessageBarBody, Spinner } from '@fluentui/react-components'

import * as strings from 'ProvisionWebPartsStrings'
import { FieldContainer } from '../../../FieldContainer'
import type { IGuestInput } from '../../../../models/IGuestRequest'
import styles from './GuestProfileForm.module.scss'

interface IGuestProfileFormProps {
  guest: IGuestInput
  onChange: (partial: Partial<IGuestInput>) => void
  disabled?: boolean
}

export const GuestProfileForm: React.FC<IGuestProfileFormProps> = ({
  guest,
  onChange,
  disabled
}) => {
  if (guest.loading) {
    return (
      <div className={styles.loading}>
        <Spinner size='tiny' label={`${guest.email}…`} />
      </div>
    )
  }

  const readOnly = guest.exists
  const isDisabled = disabled || readOnly
  const missingFirstName = readOnly && !guest.firstName.trim()
  const missingLastName = readOnly && !guest.lastName.trim()
  const hasMissingNames = missingFirstName || missingLastName

  return (
    <div className={styles.form}>
      {guest.exists && !hasMissingNames && (
        <MessageBar intent='success'>
          <MessageBarBody>{strings.GuestExistsBadge}</MessageBarBody>
        </MessageBar>
      )}
      {hasMissingNames && (
        <MessageBar intent='warning'>
          <MessageBarBody>{strings.GuestExistsMissingDetails}</MessageBarBody>
        </MessageBar>
      )}
      <div className={styles.row}>
        <FieldContainer
          label={strings.FirstNameLabel}
          iconName='Person'
          description={strings.FirstNameDescription}>
          <Input
            value={guest.firstName}
            onChange={(_, data) => onChange({ firstName: data.value })}
            placeholder={missingFirstName ? strings.NoValuePlaceholder : undefined}
            disabled={isDisabled}
            readOnly={readOnly}
          />
        </FieldContainer>
        <FieldContainer
          label={strings.LastNameLabel}
          iconName='Person'
          description={strings.LastNameDescription}>
          <Input
            value={guest.lastName}
            onChange={(_, data) => onChange({ lastName: data.value })}
            placeholder={missingLastName ? strings.NoValuePlaceholder : undefined}
            disabled={isDisabled}
            readOnly={readOnly}
          />
        </FieldContainer>
      </div>
      <FieldContainer
        label={strings.CompanyLabel}
        iconName='Building'
        description={strings.CompanyDescription}>
        <Input
          value={guest.company}
          onChange={(_, data) => onChange({ company: data.value })}
          disabled={disabled}
        />
      </FieldContainer>
    </div>
  )
}
