import * as React from 'react'
import {
  FluentProvider,
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
import type { DrawerState, IExternalPartiesProps } from './types'
import styles from './ExternalParties.module.scss'

/**
 * Samarbeidsparter: overview of the external project manager and the parties
 * on the project site, with the access they have today. For site owners only.
 */
export const ExternalParties: React.FC<IExternalPartiesProps> = (props) => {
  const { title, description, config, partiesService, accessReader } = props
  const fluentProviderId = useId('fp-bp-external-parties')
  const [drawer, setDrawer] = React.useState<DrawerState>({ kind: 'none' })
  const state = useExternalPartiesData(config, partiesService, accessReader)

  const contextValue = React.useMemo<IExternalPartiesContext | undefined>(
    () =>
      state.data
        ? { config, data: state.data, drawer, setDrawer, refresh: state.refresh }
        : undefined,
    [config, state.data, drawer, state.refresh]
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
        {drawer.kind === 'party' && <PartyDrawer partyId={drawer.partyId} />}
        {drawer.kind === 'epl' && <EplDrawer />}
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
