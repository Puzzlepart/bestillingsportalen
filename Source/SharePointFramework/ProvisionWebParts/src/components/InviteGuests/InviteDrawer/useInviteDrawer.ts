import * as React from 'react'

import * as strings from 'ProvisionWebPartsStrings'
import { useInviteGuestsContext } from '../context'
import type {
  IInviteSettings,
  M365GroupRole,
  SPGroupAction,
  SPPermissionLevel
} from '../../../models/IGuestRequest'
import type { ISiteGroup } from '../../../services'

interface IUseInviteDrawerArgs {
  open: boolean
  onOpenChange: (open: boolean) => void
}

interface IUseInviteDrawerResult {
  selected: string[]
  setSelected: (next: string[]) => void

  isGroupConnected: boolean
  siteGroups: ISiteGroup[]
  loadingContext: boolean

  spGroupAction: SPGroupAction
  spGroupName: string | undefined
  spPermissionLevel: SPPermissionLevel | undefined
  spGroupNameValidationMessage: string | undefined
  setSpGroupAction: (action: SPGroupAction) => void
  setSpGroupName: (name: string | undefined) => void
  setSpPermissionLevel: (level: SPPermissionLevel) => void

  submitting: boolean
  submitDisabled: boolean
  submit: () => Promise<void>
  cancel: () => void
}

export function useInviteDrawer({
  open,
  onOpenChange
}: IUseInviteDrawerArgs): IUseInviteDrawerResult {
  const ctx = useInviteGuestsContext()
  const [selected, setSelected] = React.useState<string[]>([])
  const [submitting, setSubmitting] = React.useState(false)
  const [submitAttempted, setSubmitAttempted] = React.useState(false)

  const [isGroupConnected, setIsGroupConnected] = React.useState(false)
  const [siteGroups, setSiteGroups] = React.useState<ISiteGroup[]>([])
  const [loadingContext, setLoadingContext] = React.useState(false)

  const [spGroupAction, setSpGroupAction] = React.useState<SPGroupAction>('None')
  const [spGroupName, setSpGroupName] = React.useState<string | undefined>(undefined)
  const [spPermissionLevel, setSpPermissionLevel] = React.useState<SPPermissionLevel | undefined>(
    'Read'
  )

  React.useEffect(() => {
    if (!open) {
      setSelected([])
      setSpGroupAction('None')
      setSpGroupName(undefined)
      setSpPermissionLevel('Read')
      setSubmitAttempted(false)
      return
    }
    let cancelled = false
    setLoadingContext(true)
    void (async () => {
      try {
        const [siteContext, groups] = await Promise.all([
          ctx.siteService.getSiteContext(),
          ctx.siteService.getSiteGroups()
        ])
        if (cancelled) return
        setIsGroupConnected(siteContext.isGroupConnected)
        setSiteGroups(groups)
        if (siteContext.associatedVisitorGroupTitle) {
          setSpGroupAction('AddToExisting')
          setSpGroupName(siteContext.associatedVisitorGroupTitle)
        }
      } finally {
        if (!cancelled) setLoadingContext(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [open, ctx.siteService])

  const onSpGroupActionChange = React.useCallback((action: SPGroupAction) => {
    setSpGroupAction(action)
    setSpGroupName(undefined)
    setSubmitAttempted(false)
  }, [])

  const spGroupNameValidationMessage = React.useMemo(() => {
    if (!submitAttempted) return undefined
    if (spGroupAction === 'None') return undefined
    if (!spGroupName || !spGroupName.trim()) return strings.SPGroupNewNameRequired
    return undefined
  }, [submitAttempted, spGroupAction, spGroupName])

  const isSettingsValid = React.useMemo(() => {
    if (spGroupAction === 'None') return true
    return !!spGroupName && spGroupName.trim().length > 0
  }, [spGroupAction, spGroupName])

  const submit = React.useCallback(async (): Promise<void> => {
    if (selected.length === 0) return
    setSubmitAttempted(true)
    if (!isSettingsValid) return
    const m365GroupRole: M365GroupRole = isGroupConnected ? 'Guest' : 'None'
    const settings: IInviteSettings = {
      m365GroupRole,
      spGroupAction,
      spGroupName: spGroupAction !== 'None' ? spGroupName : undefined,
      spPermissionLevel: spGroupAction === 'CreateNew' ? spPermissionLevel : undefined
    }
    setSubmitting(true)
    try {
      await ctx.invite(selected, settings)
    } finally {
      setSubmitting(false)
    }
  }, [
    selected,
    isSettingsValid,
    isGroupConnected,
    spGroupAction,
    spGroupName,
    spPermissionLevel,
    ctx
  ])

  const cancel = React.useCallback(() => onOpenChange(false), [onOpenChange])

  const submitDisabled = selected.length === 0 || submitting || loadingContext

  return {
    selected,
    setSelected,
    isGroupConnected,
    siteGroups,
    loadingContext,
    spGroupAction,
    spGroupName,
    spPermissionLevel,
    spGroupNameValidationMessage,
    setSpGroupAction: onSpGroupActionChange,
    setSpGroupName,
    setSpPermissionLevel,
    submitting,
    submitDisabled,
    submit,
    cancel
  }
}
