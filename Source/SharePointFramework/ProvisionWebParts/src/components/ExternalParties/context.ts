import * as React from 'react'

import type { IPartiesConfig } from '../../services/parties'
import type { DrawerState, IExternalPartiesData, IWriteServices } from './types'

export interface IExternalPartiesContext {
  config: IPartiesConfig
  data: IExternalPartiesData
  drawer: DrawerState
  setDrawer: (drawer: DrawerState) => void
  refresh: () => Promise<void>
  services: IWriteServices
  /** Reads the access again when the panel closes, e.g. after a failed run. */
  markNeedsRefresh: () => void
}

export const ExternalPartiesContext = React.createContext<IExternalPartiesContext | undefined>(
  undefined
)

export const useExternalPartiesContext = (): IExternalPartiesContext => {
  const context = React.useContext(ExternalPartiesContext)
  if (!context) {
    throw new Error('useExternalPartiesContext must be used inside ExternalPartiesContext.Provider')
  }
  return context
}
