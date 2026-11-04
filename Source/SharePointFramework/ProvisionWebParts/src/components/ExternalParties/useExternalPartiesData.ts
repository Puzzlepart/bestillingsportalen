import * as React from 'react'

import type { IPartiesConfig, PartiesService, AccessReaderService } from '../../services/parties'
import { toServerRelativeUrl } from '../../services/parties/partyConfig'
import { buildPartyRows } from './partyRows'
import type { IExternalPartiesData } from './types'

export type AccessState = 'checking' | 'allowed' | 'denied'

export interface IExternalPartiesDataState {
  access: AccessState
  loading: boolean
  error?: string
  data?: IExternalPartiesData
  refresh: () => Promise<void>
}

/** 401 and 403 mean the user is not an owner. Everything else is shown as an error. */
const isAccessDenied = (error: Error): boolean =>
  /\[40[13]\]|access denied|ingen tilgang/i.test(error?.message || '')

/**
 * Checks that the current user is an owner, then reads the parties and the
 * access on the site. The data is read from SharePoint every time; nothing is
 * cached, so the view always shows the access as it is now.
 */
export const useExternalPartiesData = (
  config: IPartiesConfig,
  partiesService: PartiesService,
  accessReader: AccessReaderService
): IExternalPartiesDataState => {
  const [access, setAccess] = React.useState<AccessState>('checking')
  const [loading, setLoading] = React.useState(false)
  const [error, setError] = React.useState<string>()
  const [data, setData] = React.useState<IExternalPartiesData>()

  const load = React.useCallback(async () => {
    setLoading(true)
    setError(undefined)
    try {
      const site = await partiesService.getSiteInfo()
      const [parties, snapshot, guestInvitationUrl] = await Promise.all([
        partiesService.getParties(site.title, config.groupPrefix, config.externalProjectManager),
        accessReader.getSnapshot(config.librariesFilter, config.protectedLibraries),
        config.guestInvitationUrl
          ? partiesService.existingPageUrl(
              toServerRelativeUrl(site.serverRelativeUrl, config.guestInvitationUrl)
            )
          : Promise.resolve(undefined)
      ])
      setData({
        site,
        parties,
        snapshot,
        rows: buildPartyRows(parties, snapshot, config.partTypes),
        externalProjectManager: parties.find((p) => p.isExternalProjectManager),
        guestInvitationUrl
      })
    } catch (e) {
      if (isAccessDenied(e)) setAccess('denied')
      else setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }, [config, partiesService, accessReader])

  React.useEffect(() => {
    let cancelled = false
    void (async () => {
      try {
        const allowed = await partiesService.currentUserCanManage()
        if (cancelled) return
        setAccess(allowed ? 'allowed' : 'denied')
        if (allowed) await load()
      } catch {
        if (!cancelled) setAccess('denied')
      }
    })()
    return () => {
      cancelled = true
    }
  }, [partiesService, load])

  return { access, loading, error, data, refresh: load }
}
