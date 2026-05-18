import * as React from 'react'
import type { GuestRequestService } from '../../services/GuestRequestService'
import type { IGuestInput, IGuestRequest } from '../../models/IGuestRequest'

interface IUseInviteGuestsArgs {
  service: GuestRequestService
  siteUrl: string
  siteTitle: string
}

interface IUseInviteGuestsResult {
  requests: IGuestRequest[]
  loading: boolean
  error: string | undefined
  refresh: () => Promise<void>
  invite: (guests: IGuestInput[]) => Promise<void>
  retry: (itemId: number) => Promise<void>
}

export function useInviteGuests({
  service,
  siteUrl,
  siteTitle
}: IUseInviteGuestsArgs): IUseInviteGuestsResult {
  const [requests, setRequests] = React.useState<IGuestRequest[]>([])
  const [loading, setLoading] = React.useState<boolean>(true)
  const [error, setError] = React.useState<string | undefined>(undefined)

  const refresh = React.useCallback(async (): Promise<void> => {
    setLoading(true)
    setError(undefined)
    try {
      const items = await service.getForSite(siteUrl)
      setRequests(items)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }, [service, siteUrl])

  const invite = React.useCallback(
    async (guests: IGuestInput[]): Promise<void> => {
      const created = await service.createMany(guests, siteUrl, siteTitle)
      setRequests((prev) => [...created, ...prev])
    },
    [service, siteUrl, siteTitle]
  )

  const retry = React.useCallback(
    async (itemId: number): Promise<void> => {
      await service.retry(itemId)
      await refresh()
    },
    [service, refresh]
  )

  React.useEffect(() => {
    void refresh()
  }, [refresh])

  return { requests, loading, error, refresh, invite, retry }
}
