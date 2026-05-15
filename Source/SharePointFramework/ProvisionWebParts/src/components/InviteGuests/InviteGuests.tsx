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
import type { IInviteSettings } from '../../models/IGuestRequest'
import type { IInviteGuestsProps } from './types'

export const InviteGuests: React.FC<IInviteGuestsProps> = (props) => {
  const { title, description, displayMode, service, siteService, siteUrl, siteTitle, currentUser } =
    props
  const [drawerOpen, setDrawerOpen] = React.useState(false)
  const state = useInviteGuests({ service, siteUrl, siteTitle })

  const fluentProviderId = useId('fp-bp-guest-invite')
  const fluentProviderToasterId = useId('fp-bp-guest-invite-toaster')
  const toasterId = useId('bp-guest-invite-toaster-')
  const { dispatchToast } = useToastController(toasterId)

  const onInvite = React.useCallback(
    async (emails: string[], settings: IInviteSettings) => {
      try {
        await state.invite(emails, settings)
        setDrawerOpen(false)
        dispatchToast(
          <Toast>
            <ToastTitle>{strings.ToastSuccessTitle}</ToastTitle>
            <ToastBody>{strings.ToastSuccessBody}</ToastBody>
          </Toast>,
          { intent: 'success' }
        )
      } catch (e) {
        dispatchToast(
          <Toast>
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
      currentUser,
      service,
      siteService,
      requests: state.requests,
      loading: state.loading,
      error: state.error,
      refresh: state.refresh,
      invite: onInvite,
      retry: state.retry
    }),
    [siteUrl, siteTitle, currentUser, service, siteService, state, onInvite]
  )

  return (
    <IdPrefixProvider value={fluentProviderId}>
      <FluentProvider theme={webLightTheme}>
        <InviteGuestsContext.Provider value={contextValue}>
          <div className={styles.inviteGuests}>
            <div className={styles.titleRow}>
              <WebPartTitle title={title} description={description} />
              <Button
                appearance='subtle'
                icon={<PersonAdd24Regular />}
                iconPosition='before'
                onClick={() => setDrawerOpen(true)}
                style={{ alignSelf: 'flex-start', justifyContent: 'flex-start' }}
                aria-haspopup='dialog'>
                {strings.InviteButton}
              </Button>
            </div>

            {state.error && <div className={styles.error}>{state.error}</div>}

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
