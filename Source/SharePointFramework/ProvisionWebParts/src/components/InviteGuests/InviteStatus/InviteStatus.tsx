import * as React from 'react'
import {
  Button,
  Dialog,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  DialogTrigger
} from '@fluentui/react-components'
import { Dismiss24Regular, Open24Regular } from '@fluentui/react-icons'

import * as strings from 'ProvisionWebPartsStrings'
import styles from './InviteStatus.module.scss'
import { useInviteGuestsContext } from '../context'
import { StatusGrid } from './StatusGrid'
import { StatusSummary } from './StatusSummary'
import type { IInviteStatusProps } from './types'

export const InviteStatus: React.FC<IInviteStatusProps> = ({ mode }) => {
  const [dialogOpen, setDialogOpen] = React.useState(false)
  const { showStatusSummary } = useInviteGuestsContext()

  if (mode === 'inline') {
    return (
      <section className={styles.container}>
        <h3 className={styles.heading}>{strings.StatusHeader}</h3>
        <StatusGrid />
      </section>
    )
  }

  return (
    <section className={styles.container}>
      <h3 className={styles.heading}>{strings.StatusHeader}</h3>
      <div className={styles.dialogTrigger}>
        {showStatusSummary && <StatusSummary />}
        <Button
          appearance='subtle'
          icon={<Open24Regular />}
          iconPosition='before'
          onClick={() => setDialogOpen(true)}
          className={styles.viewStatusButton}
          aria-haspopup='dialog'>
          {strings.ViewStatusButton}
        </Button>
      </div>
      <Dialog
        modalType='modal'
        open={dialogOpen}
        onOpenChange={(_, data) => setDialogOpen(data.open)}>
        <DialogSurface className={styles.dialogSurface}>
          <DialogBody className={styles.dialogBody}>
            <DialogTitle
              action={
                <DialogTrigger action='close' disableButtonEnhancement>
                  <Button
                    appearance='subtle'
                    aria-label={strings.CloseButton}
                    icon={<Dismiss24Regular />}
                  />
                </DialogTrigger>
              }>
              {strings.StatusDialogTitle}
            </DialogTitle>
            <DialogContent className={styles.dialogContent}>
              <StatusGrid />
            </DialogContent>
          </DialogBody>
        </DialogSurface>
      </Dialog>
    </section>
  )
}
