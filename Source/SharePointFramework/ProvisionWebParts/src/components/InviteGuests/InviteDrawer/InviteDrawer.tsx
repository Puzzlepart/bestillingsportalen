import * as React from 'react'
import {
  Button,
  DrawerBody,
  DrawerFooter,
  DrawerHeader,
  DrawerHeaderTitle,
  OverlayDrawer,
  Spinner,
  Switch
} from '@fluentui/react-components'
import { Dismiss24Regular } from '@fluentui/react-icons'

import * as strings from 'ProvisionWebPartsStrings'
import styles from './InviteDrawer.module.scss'
import { AccessPreviewPanel } from './AccessPreviewPanel'
import { GuestPicker } from './GuestPicker'
import { GuestProfileForm } from './GuestProfileForm'
import { GuestTabList } from './GuestTabList'
import { M365GroupRoleSection } from './M365GroupRoleSection'
import { SPGroupSection } from './SPGroupSection'
import { useInviteDrawer } from './useInviteDrawer'
import { useInviteGuestsContext } from '../context'
import type { IInviteDrawerProps } from './types'

export const InviteDrawer: React.FC<IInviteDrawerProps> = ({ open, onOpenChange }) => {
  const { inviteMode, perGuestProfileMode, perGuestRoleMode } = useInviteGuestsContext()
  const {
    guests,
    addGuest,
    removeGuest,
    updateGuest,
    activeGuestEmail,
    setActiveGuestEmail,
    activeGuest,
    siteGroups,
    loadingContext,
    isGroupConnected,
    perGuestProfile,
    setUserPerGuestProfile,
    perGuestRole,
    setUserPerGuestRole,
    sharedM365GroupRole,
    setSharedM365GroupRole,
    sharedSpGroupAction,
    sharedSpGroupName,
    sharedSpPermissionLevel,
    sharedSpGroupNameValidationMessage,
    setSharedSpGroupAction,
    setSharedSpGroupName,
    setSharedSpPermissionLevel,
    submitting,
    submitDisabled,
    submit,
    cancel
  } = useInviteDrawer({ open, onOpenChange })

  const guestEmails = React.useMemo(() => guests.map((g) => g.email), [guests])
  const showTabList =
    inviteMode === 'Multi' && guests.length >= 2 && (perGuestProfile || perGuestRole)
  const showToggleRow = perGuestProfileMode === 'Optional' || perGuestRoleMode === 'Optional'

  return (
    <OverlayDrawer
      position='end'
      size='medium'
      open={open}
      onOpenChange={(_, data) => onOpenChange(data.open)}>
      <DrawerHeader>
        <DrawerHeaderTitle
          action={
            <Button
              appearance='subtle'
              aria-label={strings.CancelButton}
              icon={<Dismiss24Regular />}
              onClick={cancel}
            />
          }>
          {strings.InviteDrawerHeader}
        </DrawerHeaderTitle>
      </DrawerHeader>

      <DrawerBody>
        <div className={styles.body}>
          <p className={styles.description}>{strings.InviteDrawerDescription}</p>

          {showToggleRow && (
            <div className={styles.toggleRow}>
              {perGuestProfileMode === 'Optional' && (
                <Switch
                  label={strings.PerGuestProfileLabel}
                  checked={perGuestProfile}
                  onChange={(_, d) => setUserPerGuestProfile(d.checked)}
                  disabled={submitting}
                />
              )}
              {perGuestRoleMode === 'Optional' && (
                <Switch
                  label={strings.PerGuestRoleLabel}
                  checked={perGuestRole}
                  onChange={(_, d) => setUserPerGuestRole(d.checked)}
                  disabled={submitting}
                />
              )}
            </div>
          )}

          <GuestPicker
            mode={inviteMode}
            guests={guestEmails}
            onAdd={addGuest}
            onRemove={removeGuest}
            disabled={submitting}
          />

          {showTabList && (
            <GuestTabList
              guests={guests}
              activeEmail={activeGuestEmail}
              onSelect={setActiveGuestEmail}
            />
          )}

          {activeGuest && perGuestProfile && (
            <GuestProfileForm
              guest={activeGuest}
              onChange={(partial) => updateGuest(activeGuest.email, partial)}
              disabled={submitting}
            />
          )}

          {activeGuest && perGuestRole && (
            <>
              <M365GroupRoleSection
                role={activeGuest.m365GroupRole ?? 'Visitor'}
                onChange={(r) => updateGuest(activeGuest.email, { m365GroupRole: r })}
                disabled={submitting}
              />
              <SPGroupSection
                action={activeGuest.spGroupAction ?? 'None'}
                groupName={activeGuest.spGroupName}
                permissionLevel={activeGuest.spPermissionLevel}
                siteGroups={siteGroups}
                loading={loadingContext}
                disabled={submitting}
                onActionChange={(a) =>
                  updateGuest(activeGuest.email, { spGroupAction: a, spGroupName: undefined })
                }
                onGroupNameChange={(n) => updateGuest(activeGuest.email, { spGroupName: n })}
                onPermissionLevelChange={(l) =>
                  updateGuest(activeGuest.email, { spPermissionLevel: l })
                }
              />
              <AccessPreviewPanel
                role={activeGuest.m365GroupRole ?? 'Visitor'}
                spGroupAction={activeGuest.spGroupAction ?? 'None'}
                spGroupName={activeGuest.spGroupName}
                spPermissionLevel={activeGuest.spPermissionLevel}
                isGroupConnected={isGroupConnected}
              />
            </>
          )}

          {!perGuestRole && (
            <>
              <M365GroupRoleSection
                role={sharedM365GroupRole}
                onChange={setSharedM365GroupRole}
                disabled={submitting}
              />
              <SPGroupSection
                action={sharedSpGroupAction}
                groupName={sharedSpGroupName}
                permissionLevel={sharedSpPermissionLevel}
                siteGroups={siteGroups}
                loading={loadingContext}
                disabled={submitting}
                nameValidationMessage={sharedSpGroupNameValidationMessage}
                onActionChange={setSharedSpGroupAction}
                onGroupNameChange={setSharedSpGroupName}
                onPermissionLevelChange={setSharedSpPermissionLevel}
              />
              <AccessPreviewPanel
                role={sharedM365GroupRole}
                spGroupAction={sharedSpGroupAction}
                spGroupName={sharedSpGroupName}
                spPermissionLevel={sharedSpPermissionLevel}
                isGroupConnected={isGroupConnected}
              />
            </>
          )}
        </div>
      </DrawerBody>

      <DrawerFooter>
        <div className={styles.footer}>
          <Button appearance='secondary' onClick={cancel} disabled={submitting}>
            {strings.CancelButton}
          </Button>
          <Button
            appearance='primary'
            onClick={() => void submit()}
            disabled={submitDisabled}
            icon={submitting ? <Spinner size='tiny' /> : undefined}>
            {strings.SendInvitationsButton}
          </Button>
        </div>
      </DrawerFooter>
    </OverlayDrawer>
  )
}
