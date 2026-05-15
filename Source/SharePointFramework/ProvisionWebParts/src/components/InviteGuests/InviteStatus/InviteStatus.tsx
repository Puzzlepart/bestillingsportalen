import * as React from 'react'
import { Button } from '@fluentui/react-components'
import { Open24Regular } from '@fluentui/react-icons'

import * as strings from 'ProvisionWebPartsStrings'
import styles from './InviteStatus.module.scss'
import { StatusDialog } from './StatusDialog'
import { StatusGrid } from './StatusGrid'
import { StatusSummary } from './StatusSummary'
import type { IInviteStatusProps } from './types'

export const InviteStatus: React.FC<IInviteStatusProps> = ({ mode }) => {
  const [dialogOpen, setDialogOpen] = React.useState(false)

  if (mode === 'dialog') {
    return (
      <section className={styles.container}>
        <h3 className={styles.heading}>{strings.StatusHeader}</h3>
        <div className={styles.dialogTrigger}>
          <StatusSummary />
          <Button
            appearance='subtle'
            icon={<Open24Regular />}
            iconPosition='before'
            onClick={() => setDialogOpen(true)}
            style={{ alignSelf: 'flex-start', justifyContent: 'flex-start' }}
            aria-haspopup='dialog'>
            {strings.ViewStatusButton}
          </Button>
        </div>
        <StatusDialog open={dialogOpen} onOpenChange={setDialogOpen} />
      </section>
    )
  }

  return (
    <section className={styles.container}>
      <h3 className={styles.heading}>{strings.StatusHeader}</h3>
      <StatusGrid />
    </section>
  )
}
