import * as React from 'react'
import { Field } from '@fluentui/react-components'

import styles from './FieldContainer.module.scss'
import { IconLabel } from './IconLabel'
import type { IFieldContainerProps } from './types'

export const FieldContainer: React.FC<IFieldContainerProps> = (props) => {
  const label = props.iconName ? { children: () => <IconLabel {...props} /> } : props.label
  return (
    <div className={styles.fieldContainer} hidden={props.hidden}>
      <Field
        className={styles.field}
        label={label}
        required={props.required}
        hint={props.description ?? props.hint}
        validationState={props.validationState}
        validationMessage={props.validationMessage}>
        {props.children}
      </Field>
    </div>
  )
}
