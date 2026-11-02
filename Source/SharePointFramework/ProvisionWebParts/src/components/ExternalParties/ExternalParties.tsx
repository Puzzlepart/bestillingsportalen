import * as React from 'react'
import {
  FluentProvider,
  OverlayDrawer,
  IdPrefixProvider,
  MessageBar,
  MessageBarBody,
  Spinner,
  useId
} from '@fluentui/react-components'
import * as strings from 'ProvisionWebPartsStrings'

import { format } from '../../utils/format'
import { customLightTheme } from '../../utils/theme'
import { WebPartTitle } from '../WebPartTitle'
import { ExternalPartiesContext, type IExternalPartiesContext } from './context'
import { useExternalPartiesData } from './useExternalPartiesData'
import { PartsOverview } from './PartsOverview'
import { EplDrawer, PartyDrawer } from './PartyDrawers'
import { GrantDrawer } from './GrantDrawer'
import { NewPartWizard } from './NewPartWizard'
import type { DrawerState, IExternalPartiesProps, IWriteServices } from './types'
import styles from './ExternalParties.module.scss'

/**
 * Samarbeidsparter: overview of the external project manager and the parties
 * on the project site, with the access they have today. For site owners only.
 */
export const ExternalParties: React.FC<IExternalPartiesProps> = (props) => {
  const { title, description, config, partiesService, accessReader, createWriteServices } = props
  const fluentProviderId = useId('fp-bp-external-parties')
  const state = useExternalPartiesData(config, partiesService, accessReader)
  const { refresh } = state

  // One OverlayDrawer that stays mounted. The content is kept while it closes
  // and gets a new key each time a panel opens, so a panel always starts fresh.
  const [drawer, setDrawerState] = React.useState<DrawerState>({ kind: 'none' })
  const [drawerContent, setDrawerContent] = React.useState<{ state: DrawerState; key: number }>({
    state: { kind: 'none' },
    key: 0
  })
  const needsRefresh = React.useRef(false)
  const setDrawer = React.useCallback(
    (next: DrawerState) => {
      setDrawerState(next)
      if (next.kind !== 'none') {
        setDrawerContent((c) => ({ state: next, key: c.key + 1 }))
      } else if (needsRefresh.current) {
        needsRefresh.current = false
        void refresh()
      }
    },
    [refresh]
  )
  const markNeedsRefresh = React.useCallback(() => {
    needsRefresh.current = true
  }, [])

  // One set of write services per site and user, kept across refreshes so the
  // activity log list is only looked up once.
  const site = state.data?.site
  const servicesKey = site ? `${site.absoluteUrl}|${site.currentUserId}` : undefined
  const services = React.useMemo<IWriteServices | undefined>(
    () => (site ? createWriteServices(site) : undefined),
    [servicesKey, createWriteServices]
  )

  const contextValue = React.useMemo<IExternalPartiesContext | undefined>(
    () =>
      state.data && services
        ? { config, data: state.data, drawer, setDrawer, refresh, services, markNeedsRefresh }
        : undefined,
    [config, state.data, drawer, setDrawer, refresh, services, markNeedsRefresh]
  )

  let content: React.ReactNode
  if (state.access === 'checking' || (state.loading && !state.data)) {
    content = <Spinner size='small' label={strings.Parties.Loading} labelPosition='after' />
  } else if (state.access === 'denied') {
    content = (
      <MessageBar intent='info'>
        <MessageBarBody>{strings.Parties.NotOwnerMessage}</MessageBarBody>
      </MessageBar>
    )
  } else if (state.error && !state.data) {
    content = (
      <MessageBar intent='error'>
        <MessageBarBody>{format(strings.Parties.LoadError, state.error)}</MessageBarBody>
      </MessageBar>
    )
  } else if (contextValue) {
    content = (
      <ExternalPartiesContext.Provider value={contextValue}>
        {state.error && (
          <MessageBar intent='error'>
            <MessageBarBody>{format(strings.Parties.LoadError, state.error)}</MessageBarBody>
          </MessageBar>
        )}
        <PartsOverview />
        <OverlayDrawer
          open={drawer.kind !== 'none'}
          position='end'
          size='medium'
          onOpenChange={(_, d) => {
            if (!d.open) setDrawer({ kind: 'none' })
          }}>
          <React.Fragment key={drawerContent.key}>
            {drawerContent.state.kind === 'party' && (
              <PartyDrawer partyId={drawerContent.state.partyId} />
            )}
            {drawerContent.state.kind === 'epl' && <EplDrawer />}
            {drawerContent.state.kind === 'grant' && (
              <GrantDrawer partyId={drawerContent.state.partyId} />
            )}
            {drawerContent.state.kind === 'new' && <NewPartWizard />}
          </React.Fragment>
        </OverlayDrawer>
      </ExternalPartiesContext.Provider>
    )
  }

  return (
    <IdPrefixProvider value={fluentProviderId}>
      <FluentProvider theme={customLightTheme}>
        <div className={styles.externalParties}>
          <WebPartTitle title={title} description={description} />
          {content}
        </div>
      </FluentProvider>
    </IdPrefixProvider>
  )
}
