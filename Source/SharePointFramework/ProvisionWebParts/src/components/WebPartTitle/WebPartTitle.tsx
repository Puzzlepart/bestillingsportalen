import * as React from 'react'
import { InfoLabel } from '@fluentui/react-components'

import * as strings from 'ProvisionWebPartsStrings'
import styles from './WebPartTitle.module.scss'
import type { IWebPartTitleProps } from './types'

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
        <div
          className={styles.infoLabel}
          title={strings.WebPartTitleInfoLabelTitle.replace('{0}', description)}>
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
