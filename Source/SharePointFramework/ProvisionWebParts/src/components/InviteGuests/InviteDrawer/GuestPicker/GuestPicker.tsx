import * as React from 'react'
import {
  Avatar,
  Tag,
  TagPicker,
  TagPickerControl,
  TagPickerGroup,
  TagPickerInput,
  TagPickerList,
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
    const next = data.selectedOptions.filter((v) => isValidEmail(v))
    onChange(Array.from(new Set(next)))
    setQuery('')
  }

  const onKeyDown: React.KeyboardEventHandler<HTMLInputElement> = (e) => {
    if ((e.key === 'Enter' || e.key === ',' || e.key === ';') && isValidEmail(query)) {
      e.preventDefault()
      const next = Array.from(new Set([...selected, query.trim().toLowerCase()]))
      onChange(next)
      setQuery('')
    }
  }

  return (
    <FieldContainer
      label={strings.GuestPickerLabel}
      iconName='Guest'
      validationState={validationMessage ? 'error' : 'none'}
      validationMessage={validationMessage}>
      <TagPicker
        selectedOptions={selected}
        onOptionSelect={onOptionSelect}
        disabled={disabled}
        noPopover>
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
            onKeyDown={onKeyDown}
            aria-label={strings.GuestPickerLabel}
          />
        </TagPickerControl>
        <TagPickerList />
      </TagPicker>
    </FieldContainer>
  )
}
