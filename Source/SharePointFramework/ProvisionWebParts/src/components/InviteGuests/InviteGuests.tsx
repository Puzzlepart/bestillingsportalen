import * as React from 'react'
import {
  Button,
  FluentProvider,
  IdPrefixProvider,
  Toast,
  ToastBody,
  ToastTitle,
  Toaster,
  useId,
  useToastController,
  webLightTheme
} from '@fluentui/react-components'
import { PersonAdd24Regular } from '@fluentui/react-icons'

import * as strings from 'ProvisionWebPartsStrings'
import styles from './InviteGuests.module.scss'
import { InviteGuestsContext } from './context'
import { useInviteGuests } from './useInviteGuests'
import { InviteDrawer } from './InviteDrawer'
import { InviteStatus } from './InviteStatus'
import { WebPartTitle } from '../WebPartTitle'
import type { IGuestInput } from '../../models/IGuestRequest'
import type { IInviteGuestsProps } from './types'

export const InviteGuests: React.FC<IInviteGuestsProps> = (props) => {
  const {
    title,
    description,
    displayMode,
    inviteMode,
    inviteAccessLevel,
    perGuestProfileMode,
    perGuestRoleMode,
    defaultM365GroupRole,
    defaultSpGroupAction,
    defaultSpGroupName,
    defaultSpPermissionLevel,
    autoSelectVisitorGroup,
    lockM365GroupRole,
    lockSpGroupAction,
    showAccessPreview,
    showStatusSummary,
    showCopyRedeemUrl,
    showRetryButton,
    showColumnM365Role,
    showColumnSPGroupAction,
    showColumnSPGroupName,
    showColumnSPPermissionLevel,
    showM365GroupRoleSection,
    showSPGroupSection,
    hiddenSpGroups,
    service,
    siteService,
    graphService,
    siteUrl,
    siteTitle
  } = props
  const [drawerOpen, setDrawerOpen] = React.useState(false)
  const [canInvite, setCanInvite] = React.useState<boolean>(inviteAccessLevel === 'Anyone')
  const [accessChecked, setAccessChecked] = React.useState<boolean>(inviteAccessLevel === 'Anyone')
  const state = useInviteGuests({ service, siteUrl, siteTitle })

  React.useEffect(() => {
    if (inviteAccessLevel === 'Anyone') {
      setCanInvite(true)
      setAccessChecked(true)
      return
    }
    let cancelled = false
    void (async () => {
      try {
        const level = await siteService.getCurrentUserAccessLevel()
        if (cancelled) return
        const allowed =
          inviteAccessLevel === 'Owner'
            ? level === 'Owner'
            : level === 'Owner' || level === 'Member'
        setCanInvite(allowed)
      } catch {
        if (!cancelled) setCanInvite(false)
      } finally {
        if (!cancelled) setAccessChecked(true)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [inviteAccessLevel, siteService])

  const fluentProviderId = useId('fp-bp-guest-invite')
  const fluentProviderToasterId = useId('fp-bp-guest-invite-toaster')
  const toasterId = useId('bp-guest-invite-toaster-')
  const { dispatchToast } = useToastController(toasterId)

  const onInvite = React.useCallback(
    async (guests: IGuestInput[]) => {
      try {
        await state.invite(guests)
        setDrawerOpen(false)
        dispatchToast(
          <Toast appearance='inverted'>
            <ToastTitle>{strings.ToastSuccessTitle}</ToastTitle>
            <ToastBody>{strings.ToastSuccessBody}</ToastBody>
          </Toast>,
          { intent: 'success' }
        )
      } catch (e) {
        dispatchToast(
          <Toast appearance='inverted'>
            <ToastTitle>{strings.ToastErrorTitle}</ToastTitle>
            <ToastBody>{(e as Error).message || strings.ToastErrorBody}</ToastBody>
          </Toast>,
          { intent: 'error' }
        )
      }
    },
    [state, dispatchToast]
  )

  const contextValue = React.useMemo(
    () => ({
      siteUrl,
      siteTitle,
      inviteMode,
      perGuestProfileMode,
      perGuestRoleMode,
      defaultM365GroupRole,
      defaultSpGroupAction,
      defaultSpGroupName,
      defaultSpPermissionLevel,
      autoSelectVisitorGroup,
      lockM365GroupRole,
      lockSpGroupAction,
      showAccessPreview,
      showStatusSummary,
      showCopyRedeemUrl,
      showRetryButton,
      showColumnM365Role,
      showColumnSPGroupAction,
      showColumnSPGroupName,
      showColumnSPPermissionLevel,
      showM365GroupRoleSection,
      showSPGroupSection,
      hiddenSpGroups,
      service,
      siteService,
      graphService,
      requests: state.requests,
      loading: state.loading,
      error: state.error,
      refresh: state.refresh,
      invite: onInvite,
      retry: state.retry
    }),
    [
      siteUrl,
      siteTitle,
      inviteMode,
      perGuestProfileMode,
      perGuestRoleMode,
      defaultM365GroupRole,
      defaultSpGroupAction,
      defaultSpGroupName,
      defaultSpPermissionLevel,
      autoSelectVisitorGroup,
      lockM365GroupRole,
      lockSpGroupAction,
      showAccessPreview,
      showStatusSummary,
      showCopyRedeemUrl,
      showRetryButton,
      showColumnM365Role,
      showColumnSPGroupAction,
      showColumnSPGroupName,
      showColumnSPPermissionLevel,
      showM365GroupRoleSection,
      showSPGroupSection,
      hiddenSpGroups,
      service,
      siteService,
      graphService,
      state,
      onInvite
    ]
  )

  // Render nothing until the access check resolves, and nothing at all for users
  // who don't meet the inviteAccessLevel requirement. This deliberately swallows
  // access-related errors (e.g. a guest 403-ing on the status list / site groups)
  // — only users allowed to invite ever see the web part or its error state.
  if (!accessChecked || !canInvite) {
    return null
  }

  return (
    <IdPrefixProvider value={fluentProviderId}>
      <FluentProvider theme={webLightTheme}>
        <InviteGuestsContext.Provider value={contextValue}>
          <div className={styles.inviteGuests}>
            <div className={styles.titleRow}>
              <WebPartTitle title={title} description={description} />
              {canInvite && (
                <Button
                  appearance='subtle'
                  icon={<PersonAdd24Regular />}
                  iconPosition='before'
                  onClick={() => setDrawerOpen(true)}
                  className={styles.inviteButton}
                  aria-haspopup='dialog'>
                  {strings.InviteButton}
                </Button>
              )}
            </div>

            {state.error && (
              <div className={styles.error} role='alert'>
                {state.error}
              </div>
            )}

            <InviteStatus mode={displayMode} />

            <InviteDrawer open={drawerOpen} onOpenChange={setDrawerOpen} />
          </div>
        </InviteGuestsContext.Provider>
      </FluentProvider>
      <IdPrefixProvider value={fluentProviderToasterId}>
        <FluentProvider theme={webLightTheme}>
          <Toaster toasterId={toasterId} position='bottom-end' />
        </FluentProvider>
      </IdPrefixProvider>
    </IdPrefixProvider>
  )
}

InviteGuests.defaultProps = {
  title: 'Gjesteinvitasjon',
  description: 'Inviter eksterne gjester til området og se status på tidligere invitasjoner.',
  displayMode: 'dialog',
  inviteMode: 'Multi',
  inviteAccessLevel: 'Owner',
  perGuestProfileMode: 'Optional',
  perGuestRoleMode: 'Optional',
  defaultM365GroupRole: 'Visitor',
  defaultSpGroupAction: 'AddToExisting',
  defaultSpGroupName: '',
  defaultSpPermissionLevel: 'Read',
  autoSelectVisitorGroup: true,
  lockM365GroupRole: false,
  lockSpGroupAction: false,
  showAccessPreview: true,
  showStatusSummary: true,
  showCopyRedeemUrl: true,
  showRetryButton: true,
  showColumnM365Role: true,
  showColumnSPGroupAction: false,
  showColumnSPGroupName: true,
  showColumnSPPermissionLevel: false,
  showM365GroupRoleSection: true,
  showSPGroupSection: true,
  hiddenSpGroups: ''
} satisfies Partial<IInviteGuestsProps>
