import * as React from 'react'
import { Dropdown, Input, Option, Radio, RadioGroup, Spinner } from '@fluentui/react-components'

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

export const SPGroupSection: React.FC<ISPGroupSectionProps> = ({
  action,
  groupName,
  permissionLevel,
  siteGroups,
  loading,
  disabled,
  nameValidationMessage,
  onActionChange,
  onGroupNameChange,
  onPermissionLevelChange
}) => {
  return (
    <section className={styles.section}>
      <h4 className={styles.title}>{strings.SPGroupSectionTitle}</h4>
      <RadioGroup
        value={action}
        onChange={(_, data) => onActionChange(data.value as SPGroupAction)}
        disabled={disabled}>
        <Radio value='None' label={strings.SPGroupActionNoneLabel} />
        <Radio value='AddToExisting' label={strings.SPGroupActionExistingLabel} />
        {action === 'AddToExisting' && (
          <div className={styles.optionFields}>
            {loading ? (
              <Spinner size='tiny' label={strings.SPGroupExistingPickerPlaceholder} />
            ) : (
              <FieldContainer
                label={strings.SPGroupExistingPickerLabel}
                required
                validationState={nameValidationMessage ? 'error' : 'none'}
                validationMessage={nameValidationMessage}>
                <Dropdown
                  value={groupName ?? ''}
                  selectedOptions={groupName ? [groupName] : []}
                  onOptionSelect={(_, data) => onGroupNameChange(data.optionValue)}
                  placeholder={strings.SPGroupExistingPickerPlaceholder}
                  disabled={disabled}>
                  {siteGroups.map((g) => (
                    <Option key={g.Id} value={g.Title} text={g.Title}>
                      {g.Title}
                    </Option>
                  ))}
                </Dropdown>
              </FieldContainer>
            )}
          </div>
        )}
        <Radio value='CreateNew' label={strings.SPGroupActionNewLabel} />
        {action === 'CreateNew' && (
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
        )}
      </RadioGroup>
    </section>
  )
}
