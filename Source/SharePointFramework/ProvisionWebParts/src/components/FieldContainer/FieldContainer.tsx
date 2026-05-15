import * as React from 'react'
import { Field } from '@fluentui/react-components'

import styles from './FieldContainer.module.scss'
import type { IFieldContainerProps } from './types'

export const FieldContainer: React.FC<IFieldContainerProps> = (props) => {
  return (
    <div className={styles.fieldContainer} hidden={props.hidden}>
      <Field
        className={styles.field}
        label={props.label}
        required={props.required}
        hint={props.description ?? props.hint}
        validationState={props.validationState}
        validationMessage={props.validationMessage}>
        {props.children}
      </Field>
    </div>
  )
}
