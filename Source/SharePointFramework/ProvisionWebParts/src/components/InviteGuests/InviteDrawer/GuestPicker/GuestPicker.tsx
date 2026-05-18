import * as React from 'react'
import {
  Avatar,
  Tag,
  TagPicker,
  TagPickerControl,
  TagPickerGroup,
  TagPickerInput,
  TagPickerList,
  TagPickerOption,
  useTagPickerFilter,
  type TagPickerProps
} from '@fluentui/react-components'
import * as strings from 'ProvisionWebPartsStrings'
import { FieldContainer } from '../../../FieldContainer'
import type { IGuestPickerProps } from '../types'

const isValidEmail = (value: string): boolean => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim())

export const GuestPicker: React.FC<IGuestPickerProps> = ({ selected, onChange, disabled }) => {
  const [query, setQuery] = React.useState('')

  const validationMessage = React.useMemo(() => {
    if (!query) return undefined
    return isValidEmail(query) ? undefined : strings.GuestPickerInvalidEmail
  }, [query])

  const onOptionSelect: TagPickerProps['onOptionSelect'] = (_e, data) => {
    if (data.value === 'no-matches') return
    if (!isValidEmail(data.value)) return
    onChange(Array.from(new Set(data.selectedOptions.filter(isValidEmail))))
    setQuery('')
  }

  const children = useTagPickerFilter({
    query,
    options: [query],
    noOptionsElement: (
      <TagPickerOption value='no-matches'>{strings.GuestPickerNoOptionsText}</TagPickerOption>
    ),
    renderOption: (option) => (
      <TagPickerOption
        key={option}
        value={option}
        media={<Avatar aria-hidden name={option} color='colorful' />}>
        {option}
      </TagPickerOption>
    ),
    filter: (option) =>
      selected.indexOf(option) === -1 && option.toLowerCase().indexOf(query.toLowerCase()) !== -1
  })

  return (
    <FieldContainer
      label={strings.GuestPickerLabel}
      iconName='Guest'
      validationState={validationMessage ? 'error' : 'none'}
      validationMessage={validationMessage}>
      <TagPicker selectedOptions={selected} onOptionSelect={onOptionSelect} disabled={disabled}>
        <TagPickerControl>
          <TagPickerGroup>
            {selected.map((email) => (
              <Tag
                key={email}
                shape='rounded'
                media={<Avatar aria-hidden name={email} color='colorful' />}
                value={email}>
                {email}
              </Tag>
            ))}
          </TagPickerGroup>
          <TagPickerInput
            placeholder={strings.GuestPickerPlaceholder}
            value={query}
            onChange={(e) => setQuery(e.currentTarget.value)}
            aria-label={strings.GuestPickerLabel}
          />
        </TagPickerControl>
        <TagPickerList>{children}</TagPickerList>
      </TagPicker>
    </FieldContainer>
  )
}
