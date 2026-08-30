import {
  Body1,
  FluentProvider,
  IdPrefixProvider,
  Subtitle2,
  Text
} from '@fluentui/react-components'
import React, { FC } from 'react'
import strings from 'ProvisionWebPartsStrings'
import { customLightTheme } from '../../../utils/theme'
import { getFluentIcon } from '../../../icons'
import { IProvisionInstance } from '../../../services/provisionInstances'
import styles from './InstancePicker.module.scss'

export interface IInstancePickerProps {
  instances: IProvisionInstance[]
  onSelect: (url: string) => void
}

/**
 * Shown in Teams when the tenant registry (`bp_ProvisionUrls`) holds several
 * instances the current user has access to. The choice is remembered per
 * user, so the picker only reappears when the remembered instance is gone
 * or no longer accessible.
 */
export const InstancePicker: FC<IInstancePickerProps> = (props) => {
  return (
    <IdPrefixProvider value='bp-instance-picker'>
      <FluentProvider theme={customLightTheme}>
        <div className={styles.container}>
          <Subtitle2>{strings.Provision.InstancePickerTitle}</Subtitle2>
          <Body1>{strings.Provision.InstancePickerDescription}</Body1>
          <div className={styles.list}>
            {props.instances.map((instance) => (
              <button
                key={instance.url}
                type='button'
                className={styles.instanceButton}
                onClick={() => props.onSelect(instance.url)}>
                {getFluentIcon('Building', { size: '28px' })}
                <span className={styles.instanceText}>
                  <Text weight='semibold'>{instance.title}</Text>
                  <Text size={200} className={styles.instanceUrl}>
                    {instance.url}
                  </Text>
                </span>
              </button>
            ))}
          </div>
        </div>
      </FluentProvider>
    </IdPrefixProvider>
  )
}
