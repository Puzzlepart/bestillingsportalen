import * as React from 'react';
import {
  Button,
  DrawerBody,
  DrawerFooter,
  DrawerHeader,
  DrawerHeaderTitle,
  OverlayDrawer,
  Spinner
} from '@fluentui/react-components';
import { Dismiss24Regular } from '@fluentui/react-icons';

import * as strings from 'ProvisionWebPartsStrings';
import styles from './InviteDrawer.module.scss';
import { GuestPicker } from './GuestPicker';
import { useInviteDrawer } from './useInviteDrawer';
import type { IInviteDrawerProps } from './types';

export const InviteDrawer: React.FC<IInviteDrawerProps> = ({ open, onOpenChange }) => {
  const { selected, setSelected, submitting, submit, cancel } = useInviteDrawer({ open, onOpenChange });

  return (
    <OverlayDrawer
      position="end"
      size="medium"
      open={open}
      onOpenChange={(_, data) => onOpenChange(data.open)}
    >
      <DrawerHeader>
        <DrawerHeaderTitle
          action={
            <Button
              appearance="subtle"
              aria-label={strings.CancelButton}
              icon={<Dismiss24Regular />}
              onClick={cancel}
            />
          }
        >
          {strings.InviteDrawerHeader}
        </DrawerHeaderTitle>
      </DrawerHeader>

      <DrawerBody>
        <div className={styles.body}>
          <p className={styles.description}>{strings.InviteDrawerDescription}</p>
          <GuestPicker selected={selected} onChange={setSelected} disabled={submitting} />
        </div>
      </DrawerBody>

      <DrawerFooter>
        <div className={styles.footer}>
          <Button appearance="secondary" onClick={cancel} disabled={submitting}>
            {strings.CancelButton}
          </Button>
          <Button
            appearance="primary"
            onClick={() => void submit()}
            disabled={selected.length === 0 || submitting}
            icon={submitting ? <Spinner size="tiny" /> : undefined}
          >
            {strings.SendInvitationsButton}
          </Button>
        </div>
      </DrawerFooter>
    </OverlayDrawer>
  );
};
