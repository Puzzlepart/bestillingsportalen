import * as React from 'react'
import {
  Button,
  CounterBadge,
  DrawerBody,
  DrawerFooter,
  DrawerHeader,
  DrawerHeaderTitle,
  OverlayDrawer,
  Popover,
  PopoverSurface,
  PopoverTrigger,
  Spinner,
  Switch
} from '@fluentui/react-components'
import { Dismiss24Regular, Options24Regular } from '@fluentui/react-icons'

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
  const { inviteMode, perGuestProfileMode, perGuestRoleMode, showAccessPreview } =
    useInviteGuestsContext()
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
  const activeToggleCount = (perGuestProfile ? 1 : 0) + (perGuestRole ? 1 : 0)

  return (
    <OverlayDrawer
      position='end'
      size='medium'
      open={open}
      onOpenChange={(_, data) => onOpenChange(data.open)}>
      <DrawerHeader>
        <DrawerHeaderTitle
          action={
            <div className={styles.headerActions}>
              {showToggleRow && (
                <Popover>
                  <PopoverTrigger>
                    <Button
                      appearance='subtle'
                      icon={<Options24Regular />}
                      aria-label={strings.ViewSettingsLabel}>
                      {activeToggleCount > 0 && (
                        <CounterBadge
                          count={activeToggleCount}
                          size='small'
                          appearance='filled'
                          color='brand'
                        />
                      )}
                    </Button>
                  </PopoverTrigger>
                  <PopoverSurface>
                    <div className={styles.popoverBody}>
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
                  </PopoverSurface>
                </Popover>
              )}
              <Button
                appearance='subtle'
                aria-label={strings.CancelButton}
                icon={<Dismiss24Regular />}
                onClick={cancel}
              />
            </div>
          }>
          {strings.InviteDrawerHeader}
        </DrawerHeaderTitle>
      </DrawerHeader>

      <DrawerBody>
        <div className={styles.body}>
          <p className={styles.description}>{strings.InviteDrawerDescription}</p>

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
              {showAccessPreview && (
                <AccessPreviewPanel
                  role={activeGuest.m365GroupRole ?? 'Visitor'}
                  spGroupAction={activeGuest.spGroupAction ?? 'None'}
                  spGroupName={activeGuest.spGroupName}
                  spPermissionLevel={activeGuest.spPermissionLevel}
                  isGroupConnected={isGroupConnected}
                />
              )}
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
              {showAccessPreview && (
                <AccessPreviewPanel
                  role={sharedM365GroupRole}
                  spGroupAction={sharedSpGroupAction}
                  spGroupName={sharedSpGroupName}
                  spPermissionLevel={sharedSpPermissionLevel}
                  isGroupConnected={isGroupConnected}
                />
              )}
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
