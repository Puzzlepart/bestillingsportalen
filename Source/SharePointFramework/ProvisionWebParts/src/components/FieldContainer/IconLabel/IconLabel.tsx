import * as React from 'react'
import { Label } from '@fluentui/react-components'

import { getFluentIcon } from '../../../icons'
import type { IFieldContainerProps } from '../types'
import styles from './IconLabel.module.scss'

export const IconLabel: React.FC<IFieldContainerProps> = (props) => {
  return (
    <div className={styles.iconLabel}>
      {props.iconName && getFluentIcon(props.iconName)}
      <Label size='small' weight='semibold' required={props.required}>
        {props.label}
      </Label>
    </div>
  )
}
