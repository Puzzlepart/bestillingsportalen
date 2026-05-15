import * as React from 'react';
import {
  Button,
  Dialog,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  DialogTrigger
} from '@fluentui/react-components';
import { Dismiss24Regular } from '@fluentui/react-icons';

import * as strings from 'ProvisionWebPartsStrings';
import styles from './InviteStatus.module.scss';
import { StatusGrid } from './StatusGrid';

interface IStatusDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export const StatusDialog: React.FC<IStatusDialogProps> = ({ open, onOpenChange }) => {
  return (
    <Dialog
      modalType="non-modal"
      open={open}
      onOpenChange={(_, data) => onOpenChange(data.open)}
    >
      <DialogSurface className={styles.dialogSurface}>
        <DialogBody>
          <DialogTitle
            action={
              <DialogTrigger action="close" disableButtonEnhancement>
                <Button
                  appearance="subtle"
                  aria-label={strings.CloseButton}
                  icon={<Dismiss24Regular />}
                />
              </DialogTrigger>
            }
          >
            {strings.StatusDialogTitle}
          </DialogTitle>
          <DialogContent className={styles.dialogContent}>
            <StatusGrid />
          </DialogContent>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
};
