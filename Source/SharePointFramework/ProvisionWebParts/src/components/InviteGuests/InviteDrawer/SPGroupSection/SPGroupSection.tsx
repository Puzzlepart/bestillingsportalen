import * as React from 'react'
import {
  Dropdown,
  Input,
  Option,
  OptionGroup,
  Radio,
  RadioGroup,
  Spinner,
  Tooltip
} from '@fluentui/react-components'
import { LockClosed16Regular } from '@fluentui/react-icons'

import * as strings from 'ProvisionWebPartsStrings'
import { FieldContainer } from '../../../FieldContainer'
import type { SPGroupActionUI, SPPermissionLevel } from '../../../../models/IGuestRequest'
import type { ISiteGroup } from '../../../../services'
import { groupDisplayName, type GroupSectionKey, type IGroupOptionSection } from './groupOptions'
import styles from './SPGroupSection.module.scss'

interface ISPGroupSectionProps {
  /** Context-dependent helper text: with the guest role the section is a pure
   * add-on (the M365 group already grants access); without it, an SP group is
   * the only way the invite grants site access. */
  description?: string
  /** Label for the 'None' action. With the guest role the guest still lands in
   * the standard member group via the M365 group, so "do not add" would be
   * misleading — the caller passes "only the standard group" instead. */
  noneLabel?: string
  action: SPGroupActionUI
  groupName?: string
  permissionLevel?: SPPermissionLevel
  siteGroups: ISiteGroup[]
  /** The groups in sections: fixed roles, partners and other groups, with short names. */
  groupSections: IGroupOptionSection[]
  loading: boolean
  disabled?: boolean
  locked?: boolean
  presetGroupName?: string
  actionOptions: SPGroupActionUI[]
  nameValidationMessage?: string
  onActionChange: (action: SPGroupActionUI) => void
  onGroupNameChange: (name: string | undefined) => void
  onPermissionLevelChange: (level: SPPermissionLevel) => void
}

const SECTION_LABELS: Record<GroupSectionKey, string> = {
  fixed: strings.SPGroupSectionFixedRoles,
  parties: strings.SPGroupSectionParties,
  other: strings.SPGroupSectionOther
}

/** One group in the picker: the short name, with the party type or permission level. */
const renderOption = ({
  group,
  displayName,
  secondary
}: IGroupOptionSection['options'][number]) => (
  <Option key={group.Id} value={group.Title} text={displayName}>
    <span className={styles.groupOption}>
      <span>{displayName}</span>
      {secondary && <span className={styles.groupPermission}>{secondary}</span>}
    </span>
  </Option>
)

const PERMISSION_OPTIONS: { key: SPPermissionLevel; labelKey: keyof typeof strings }[] = [
  { key: 'Read', labelKey: 'SPPermissionRead' },
  { key: 'Contribute', labelKey: 'SPPermissionContribute' },
  { key: 'Edit', labelKey: 'SPPermissionEdit' },
  { key: 'Full Control', labelKey: 'SPPermissionFullControl' }
]

const actionLabel = (action: SPGroupActionUI): string => {
  switch (action) {
    case 'None':
      return strings.SPGroupActionNoneLabel
    case 'AddToExisting':
      return strings.SPGroupActionExistingLabel
    case 'CreateNew':
      return strings.SPGroupActionNewLabel
    case 'Preset':
      return strings.SPGroupActionPresetLabel
  }
}

const formatLockedLabel = (template: string, value: string): string =>
  template.replace('{0}', value)

export const SPGroupSection: React.FC<ISPGroupSectionProps> = ({
  description,
  noneLabel,
  action,
  groupName,
  permissionLevel,
  siteGroups,
  groupSections,
  loading,
  disabled,
  locked,
  presetGroupName,
  actionOptions,
  nameValidationMessage,
  onActionChange,
  onGroupNameChange,
  onPermissionLevelChange
}) => {
  const presetPermissionLevel = presetGroupName
    ? siteGroups.find((g) => g.Title === presetGroupName)?.PermissionLevel
    : undefined

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
            value={groupName ? groupDisplayName(groupSections, groupName) : ''}
            selectedOptions={groupName ? [groupName] : []}
            onOptionSelect={(_, data) => onGroupNameChange(data.optionValue)}
            placeholder={strings.SPGroupExistingPickerPlaceholder}
            disabled={disabled}
            listbox={{ className: styles.groupDropdown }}>
            {groupSections.length === 1
              ? groupSections[0].options.map(renderOption)
              : groupSections.map((section) => (
                  <OptionGroup key={section.key} label={SECTION_LABELS[section.key]}>
                    {section.options.map(renderOption)}
                  </OptionGroup>
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
      {description && <p className={styles.description}>{description}</p>}
      {locked ? (
        <>
          <span className={styles.lockedValue}>
            <Tooltip content={strings.LockedFieldTooltip} relationship='label'>
              <LockClosed16Regular tabIndex={0} />
            </Tooltip>
            {formatLockedLabel(
              strings.LockedActionLabel,
              action === 'None' ? (noneLabel ?? actionLabel(action)) : actionLabel(action)
            )}
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
          onChange={(_, data) => onActionChange(data.value as SPGroupActionUI)}
          disabled={disabled}>
          {actionOptions.map((key) => {
            switch (key) {
              case 'None':
                return (
                  <Radio
                    key='None'
                    value='None'
                    label={noneLabel ?? strings.SPGroupActionNoneLabel}
                  />
                )
              case 'AddToExisting':
                return (
                  <React.Fragment key='AddToExisting'>
                    <Radio value='AddToExisting' label={strings.SPGroupActionExistingLabel} />
                    {addToExistingFields}
                  </React.Fragment>
                )
              case 'CreateNew':
                return (
                  <React.Fragment key='CreateNew'>
                    <Radio value='CreateNew' label={strings.SPGroupActionNewLabel} />
                    {createNewFields}
                  </React.Fragment>
                )
              case 'Preset':
                return presetGroupName ? (
                  <Radio
                    key='Preset'
                    value='Preset'
                    label={
                      <span className={styles.groupOption}>
                        <span>
                          {formatLockedLabel(strings.SPGroupActionPresetTemplate, presetGroupName)}
                        </span>
                        {presetPermissionLevel && (
                          <span className={styles.groupPermission}>{presetPermissionLevel}</span>
                        )}
                      </span>
                    }
                  />
                ) : null
              default:
                return null
            }
          })}
        </RadioGroup>
      )}
    </section>
  )
}
