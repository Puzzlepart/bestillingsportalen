import * as React from 'react'
import { InfoLabel } from '@fluentui/react-components'

import * as strings from 'ProvisionWebPartsStrings'
import styles from './WebPartTitle.module.scss'
import type { IWebPartTitleProps } from './types'

const formatTooltip = (description: string): string => {
  const template = strings.WebPartTitleInfoLabelTitle
  return template ? template.replace('{0}', description) : description
}

export const WebPartTitle: React.FC<IWebPartTitleProps> = ({ title, description }) => {
  if (!title && !description) return null

  return (
    <div className={styles.root}>
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
    </div>
  )
}
