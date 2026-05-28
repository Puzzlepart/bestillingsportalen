import * as React from 'react'
import {
  Dropdown,
  Input,
  Option,
  Radio,
  RadioGroup,
  Spinner,
  Tooltip
} from '@fluentui/react-components'
import { LockClosed16Regular } from '@fluentui/react-icons'

import * as strings from 'ProvisionWebPartsStrings'
import { FieldContainer } from '../../../FieldContainer'
import type { SPGroupAction, SPPermissionLevel } from '../../../../models/IGuestRequest'
import type { ISiteGroup } from '../../../../services'
import styles from './SPGroupSection.module.scss'

interface ISPGroupSectionProps {
  action: SPGroupAction
  groupName?: string
  permissionLevel?: SPPermissionLevel
  siteGroups: ISiteGroup[]
  loading: boolean
  disabled?: boolean
  locked?: boolean
  nameValidationMessage?: string
  onActionChange: (action: SPGroupAction) => void
  onGroupNameChange: (name: string | undefined) => void
  onPermissionLevelChange: (level: SPPermissionLevel) => void
}

const PERMISSION_OPTIONS: { key: SPPermissionLevel; labelKey: keyof typeof strings }[] = [
  { key: 'Read', labelKey: 'SPPermissionRead' },
  { key: 'Contribute', labelKey: 'SPPermissionContribute' },
  { key: 'Edit', labelKey: 'SPPermissionEdit' },
  { key: 'Full Control', labelKey: 'SPPermissionFullControl' }
]

const actionLabel = (action: SPGroupAction): string => {
  switch (action) {
    case 'None':
      return strings.SPGroupActionNoneLabel
    case 'AddToExisting':
      return strings.SPGroupActionExistingLabel
    case 'CreateNew':
      return strings.SPGroupActionNewLabel
  }
}

const formatLockedLabel = (template: string, value: string): string =>
  template.replace('{0}', value)

export const SPGroupSection: React.FC<ISPGroupSectionProps> = ({
  action,
  groupName,
  permissionLevel,
  siteGroups,
  loading,
  disabled,
  locked,
  nameValidationMessage,
  onActionChange,
  onGroupNameChange,
  onPermissionLevelChange
}) => {
  const addToExistingFields = action === 'AddToExisting' && (
    <div className={styles.optionFields}>
      {loading ? (
        <Spinner size='tiny' label={strings.SPGroupExistingPickerPlaceholder} />
      ) : locked && groupName ? (
        <span className={styles.lockedValue}>
          <Tooltip content={strings.LockedFieldTooltip} relationship='label'>
            <LockClosed16Regular role='img' aria-label={strings.LockedFieldTooltip} tabIndex={0} />
          </Tooltip>
          {formatLockedLabel(strings.LockedGroupNameLabel, groupName)}
        </span>
      ) : (
        <FieldContainer
          label={strings.SPGroupExistingPickerLabel}
          required
          validationState={nameValidationMessage ? 'error' : 'none'}
          validationMessage={nameValidationMessage}>
          <Dropdown
            className={styles.groupDropdown}
            value={groupName ?? ''}
            selectedOptions={groupName ? [groupName] : []}
            onOptionSelect={(_, data) => onGroupNameChange(data.optionValue)}
            placeholder={strings.SPGroupExistingPickerPlaceholder}
            disabled={disabled}
            listbox={{ className: styles.groupDropdown }}>
            {siteGroups.map((g) => (
              <Option key={g.Id} value={g.Title} text={g.Title}>
                <span className={styles.groupOption}>
                  <span>{g.Title}</span>
                  {g.PermissionLevel && (
                    <span className={styles.groupPermission}>{g.PermissionLevel}</span>
                  )}
                </span>
              </Option>
            ))}
          </Dropdown>
        </FieldContainer>
      )}
    </div>
  )

  const createNewFields = action === 'CreateNew' && (
    <div className={styles.optionFields}>
      <FieldContainer
        label={strings.SPGroupNewNameLabel}
        required
        validationState={nameValidationMessage ? 'error' : 'none'}
        validationMessage={nameValidationMessage}>
        <Input
          value={groupName ?? ''}
          onChange={(_, data) => onGroupNameChange(data.value || undefined)}
          placeholder={strings.SPGroupNewNamePlaceholder}
          disabled={disabled}
        />
      </FieldContainer>
      <FieldContainer label={strings.SPGroupNewPermissionLabel} required>
        <Dropdown
          value={
            permissionLevel
              ? (strings[
                  PERMISSION_OPTIONS.find((p) => p.key === permissionLevel)!.labelKey
                ] as string)
              : ''
          }
          selectedOptions={permissionLevel ? [permissionLevel] : []}
          onOptionSelect={(_, data) =>
            onPermissionLevelChange(data.optionValue as SPPermissionLevel)
          }
          disabled={disabled}>
          {PERMISSION_OPTIONS.map((p) => (
            <Option key={p.key} value={p.key} text={strings[p.labelKey] as string}>
              {strings[p.labelKey] as string}
            </Option>
          ))}
        </Dropdown>
      </FieldContainer>
    </div>
  )

  return (
    <section className={styles.section}>
      <h4 className={styles.title}>{strings.SPGroupSectionTitle}</h4>
      {locked ? (
        <>
          <span className={styles.lockedValue}>
            <Tooltip content={strings.LockedFieldTooltip} relationship='label'>
              <LockClosed16Regular tabIndex={0} />
            </Tooltip>
            {formatLockedLabel(strings.LockedActionLabel, actionLabel(action))}
          </span>
          {(addToExistingFields || createNewFields) && (
            <div className={styles.lockedFields}>
              {addToExistingFields}
              {createNewFields}
            </div>
          )}
        </>
      ) : (
        <RadioGroup
          value={action}
          onChange={(_, data) => onActionChange(data.value as SPGroupAction)}
          disabled={disabled}>
          <Radio value='None' label={strings.SPGroupActionNoneLabel} />
          <Radio value='AddToExisting' label={strings.SPGroupActionExistingLabel} />
          {addToExistingFields}
          <Radio value='CreateNew' label={strings.SPGroupActionNewLabel} />
          {createNewFields}
        </RadioGroup>
      )}
    </section>
  )
}
