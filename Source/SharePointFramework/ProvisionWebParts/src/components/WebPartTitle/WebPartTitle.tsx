import * as React from 'react'
import {
  FluentProvider,
  IdPrefixProvider,
  InfoLabel,
  useId,
  webLightTheme
} from '@fluentui/react-components'

import * as strings from 'ProvisionWebPartsStrings'
import styles from './WebPartTitle.module.scss'
import type { IWebPartTitleProps } from './types'

const formatTooltip = (description: string): string => {
  const template = strings.WebPartTitleInfoLabelTitle
  return template ? template.replace('{0}', description) : description
}

export const WebPartTitle: React.FC<IWebPartTitleProps> = ({ title, description }) => {
  const fluentProviderId = useId('fp-bp-webpart-title')
  if (!title && !description) return null

  return (
    <IdPrefixProvider value={fluentProviderId}>
      <FluentProvider className={styles.root} theme={webLightTheme}>
        <h2 className={styles.heading} title={title} hidden={!title}>
          <span role='heading' aria-level={2} className={styles.title}>
            {title}
          </span>
        </h2>
        {description && (
          <div className={styles.infoLabel} title={formatTooltip(description)}>
            <InfoLabel
              size='large'
              info={
                <div
                  className={styles.infoLabelContent}
                  dangerouslySetInnerHTML={{ __html: description }}
                />
              }
            />
          </div>
        )}
      </FluentProvider>
    </IdPrefixProvider>
  )
}
