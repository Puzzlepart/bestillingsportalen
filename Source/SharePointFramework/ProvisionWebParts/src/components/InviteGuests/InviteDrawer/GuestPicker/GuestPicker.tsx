import * as React from 'react'
import {
  Avatar,
  Button,
  Input,
  Tag,
  TagPicker,
  TagPickerControl,
  TagPickerGroup,
  TagPickerInput,
  TagPickerList,
  TagPickerOption,
  useTagPickerFilter,
  type InputProps,
  type TagPickerProps
} from '@fluentui/react-components'
import { DismissCircle20Regular } from '@fluentui/react-icons'
import * as strings from 'ProvisionWebPartsStrings'
import { FieldContainer } from '../../../FieldContainer'
import { isValidEmail } from '../../../../utils'
import type { IGuestPickerProps } from '../types'

export const GuestPicker: React.FC<IGuestPickerProps> = ({
  mode,
  guests,
  onAdd,
  onRemove,
  disabled
}) => {
  const [query, setQuery] = React.useState('')

  const validationMessage = React.useMemo(() => {
    if (!query) return undefined
    return isValidEmail(query) ? undefined : strings.GuestPickerInvalidEmail
  }, [query])

  if (mode === 'Single') {
    const value = guests[0] ?? ''
    const onSingleChange: InputProps['onChange'] = (_e, data) => {
      const next = (data.value || '').trim().toLowerCase()
      if (value && value !== next) onRemove(value)
      if (next && isValidEmail(next)) onAdd(next)
    }
    return (
      <FieldContainer
        label={strings.GuestPickerLabel}
        iconName='Guest'
        description={strings.GuestPickerHelperText}
        validationState={value && !isValidEmail(value) ? 'error' : 'none'}
        validationMessage={
          value && !isValidEmail(value) ? strings.GuestPickerInvalidEmail : undefined
        }>
        <Input
          type='email'
          value={value}
          onChange={onSingleChange}
          placeholder={strings.GuestPickerPlaceholder}
          disabled={disabled}
          contentAfter={
            value ? (
              <Button
                appearance='transparent'
                size='small'
                icon={<DismissCircle20Regular />}
                aria-label={strings.ClearFieldLabel}
                onClick={() => onRemove(value)}
                disabled={disabled}
              />
            ) : undefined
          }
        />
      </FieldContainer>
    )
  }

  const onOptionSelect: TagPickerProps['onOptionSelect'] = (_e, data) => {
    if (data.value === 'no-matches') return
    if (!isValidEmail(data.value)) return
    if (guests.indexOf(data.value) === -1) onAdd(data.value)
    else onRemove(data.value)
    setQuery('')
  }

  const onMultiInputChange = (e: React.ChangeEvent<HTMLInputElement>): void => {
    const value = e.currentTarget.value
    if (/[,;\n]/.test(value)) {
      const parts = value
        .split(/[,;\n]+/)
        .map((p) => p.trim().toLowerCase())
        .filter((p) => p && isValidEmail(p))
      parts.forEach((p) => {
        if (guests.indexOf(p) === -1) onAdd(p)
      })
      setQuery('')
      return
    }
    setQuery(value)
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
      guests.indexOf(option) === -1 && option.toLowerCase().indexOf(query.toLowerCase()) !== -1
  })

  return (
    <FieldContainer
      label={strings.GuestPickerLabel}
      iconName='Guest'
      description={strings.GuestPickerHelperText}
      validationState={validationMessage ? 'error' : 'none'}
      validationMessage={validationMessage}>
      <TagPicker selectedOptions={guests} onOptionSelect={onOptionSelect} disabled={disabled}>
        <TagPickerControl
          secondaryAction={
            query || guests.length > 0 ? (
              <Button
                appearance='transparent'
                size='small'
                icon={<DismissCircle20Regular />}
                aria-label={strings.ClearFieldLabel}
                onClick={() => {
                  guests.forEach((g) => onRemove(g))
                  setQuery('')
                }}
                disabled={disabled}
              />
            ) : undefined
          }>
          <TagPickerGroup>
            {guests.map((email) => (
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
            onChange={onMultiInputChange}
            aria-label={strings.GuestPickerLabel}
          />
        </TagPickerControl>
        <TagPickerList>{children}</TagPickerList>
      </TagPicker>
    </FieldContainer>
  )
}
