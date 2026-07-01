import * as React from 'react'
import type { IInviteGuestsContext } from './types'

export const InviteGuestsContext = React.createContext<IInviteGuestsContext | undefined>(undefined)

export function useInviteGuestsContext(): IInviteGuestsContext {
  const ctx = React.useContext(InviteGuestsContext)
  if (!ctx) {
    throw new Error('useInviteGuestsContext must be used inside <InviteGuestsContext.Provider>')
  }
  return ctx
}
