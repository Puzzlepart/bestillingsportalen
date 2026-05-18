import * as React from 'react'

import * as strings from 'ProvisionWebPartsStrings'
import { useInviteGuestsContext } from '../context'
import type {
  FeatureToggleMode,
  IGuestInput,
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
  guests: IGuestInput[]
  addGuest: (email: string) => void
  removeGuest: (email: string) => void
  updateGuest: (email: string, partial: Partial<IGuestInput>) => void

  activeGuestEmail: string | undefined
  setActiveGuestEmail: (email: string) => void
  activeGuest: IGuestInput | undefined

  siteGroups: ISiteGroup[]
  loadingContext: boolean

  perGuestProfile: boolean
  setUserPerGuestProfile: (value: boolean) => void
  perGuestRole: boolean
  setUserPerGuestRole: (value: boolean) => void

  sharedM365GroupRole: M365GroupRole
  setSharedM365GroupRole: (role: M365GroupRole) => void

  sharedSpGroupAction: SPGroupAction
  sharedSpGroupName: string | undefined
  sharedSpPermissionLevel: SPPermissionLevel | undefined
  sharedSpGroupNameValidationMessage: string | undefined
  setSharedSpGroupAction: (action: SPGroupAction) => void
  setSharedSpGroupName: (name: string | undefined) => void
  setSharedSpPermissionLevel: (level: SPPermissionLevel) => void

  submitting: boolean
  submitDisabled: boolean
  submit: () => Promise<void>
  cancel: () => void
}

const isValidEmail = (value: string): boolean => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim())

const resolveToggle = (mode: FeatureToggleMode, userValue: boolean): boolean => {
  if (mode === 'Enforced') return true
  if (mode === 'Disabled') return false
  return userValue
}

export function useInviteDrawer({
  open,
  onOpenChange
}: IUseInviteDrawerArgs): IUseInviteDrawerResult {
  const ctx = useInviteGuestsContext()
  const [guests, setGuests] = React.useState<IGuestInput[]>([])
  const [activeGuestEmail, setActiveGuestEmail] = React.useState<string | undefined>(undefined)
  const [submitting, setSubmitting] = React.useState(false)
  const [submitAttempted, setSubmitAttempted] = React.useState(false)

  const [siteGroups, setSiteGroups] = React.useState<ISiteGroup[]>([])
  const [loadingContext, setLoadingContext] = React.useState(false)

  const [userPerGuestProfile, setUserPerGuestProfile] = React.useState(false)
  const [userPerGuestRole, setUserPerGuestRole] = React.useState(false)
  const perGuestProfile = resolveToggle(ctx.perGuestProfileMode, userPerGuestProfile)
  const perGuestRole = resolveToggle(ctx.perGuestRoleMode, userPerGuestRole)

  const [sharedM365GroupRole, setSharedM365GroupRole] = React.useState<M365GroupRole>('Visitor')
  const [sharedSpGroupAction, setSharedSpGroupAction] = React.useState<SPGroupAction>('None')
  const [sharedSpGroupName, setSharedSpGroupName] = React.useState<string | undefined>(undefined)
  const [sharedSpPermissionLevel, setSharedSpPermissionLevel] = React.useState<
    SPPermissionLevel | undefined
  >('Read')

  React.useEffect(() => {
    if (!open) {
      setGuests([])
      setActiveGuestEmail(undefined)
      setUserPerGuestProfile(false)
      setUserPerGuestRole(false)
      setSharedM365GroupRole('Visitor')
      setSharedSpGroupAction('None')
      setSharedSpGroupName(undefined)
      setSharedSpPermissionLevel('Read')
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
        setSiteGroups(groups)
        if (siteContext.associatedVisitorGroupTitle) {
          setSharedSpGroupAction('AddToExisting')
          setSharedSpGroupName(siteContext.associatedVisitorGroupTitle)
        }
      } finally {
        if (!cancelled) setLoadingContext(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [open, ctx.siteService])

  const guestsRef = React.useRef<IGuestInput[]>([])
  React.useEffect(() => {
    guestsRef.current = guests
  }, [guests])

  const addGuest = React.useCallback(
    (rawEmail: string) => {
      const email = rawEmail.trim().toLowerCase()
      if (!isValidEmail(email)) return
      if (guestsRef.current.some((g) => g.email === email)) return
      const next: IGuestInput = {
        email,
        firstName: '',
        lastName: '',
        company: '',
        exists: false,
        loading: true
      }
      setGuests((prev) => [...prev, next])
      setActiveGuestEmail((current) => current ?? email)
      void (async () => {
        const result = await ctx.graphService.lookupUser(email)
        setGuests((prev) =>
          prev.map((g) =>
            g.email === email
              ? {
                  ...g,
                  loading: false,
                  exists: result.exists,
                  firstName: result.givenName ?? g.firstName,
                  lastName: result.surname ?? g.lastName,
                  displayName: result.displayName
                }
              : g
          )
        )
      })()
    },
    [ctx.graphService]
  )

  const removeGuest = React.useCallback((email: string) => {
    setGuests((prev) => prev.filter((g) => g.email !== email))
    setActiveGuestEmail((current) => {
      if (current !== email) return current
      const remaining = guestsRef.current.filter((g) => g.email !== email)
      return remaining[0]?.email
    })
  }, [])

  const updateGuest = React.useCallback((email: string, partial: Partial<IGuestInput>) => {
    setGuests((prev) => prev.map((g) => (g.email === email ? { ...g, ...partial } : g)))
  }, [])

  const activeGuest = React.useMemo(
    () => guests.find((g) => g.email === activeGuestEmail),
    [guests, activeGuestEmail]
  )

  const onSharedSpGroupActionChange = React.useCallback((action: SPGroupAction) => {
    setSharedSpGroupAction(action)
    setSharedSpGroupName(undefined)
    setSubmitAttempted(false)
  }, [])

  const sharedSpGroupNameValidationMessage = React.useMemo(() => {
    if (!submitAttempted) return undefined
    if (perGuestRole) return undefined
    if (sharedSpGroupAction === 'None') return undefined
    if (!sharedSpGroupName || !sharedSpGroupName.trim()) return strings.SPGroupNewNameRequired
    return undefined
  }, [submitAttempted, perGuestRole, sharedSpGroupAction, sharedSpGroupName])

  const isSettingsValid = React.useMemo(() => {
    if (perGuestRole) {
      return guests.every((g) => {
        const action = g.spGroupAction ?? 'None'
        if (action === 'None') return true
        return !!g.spGroupName && g.spGroupName.trim().length > 0
      })
    }
    if (sharedSpGroupAction === 'None') return true
    return !!sharedSpGroupName && sharedSpGroupName.trim().length > 0
  }, [perGuestRole, guests, sharedSpGroupAction, sharedSpGroupName])

  const submit = React.useCallback(async (): Promise<void> => {
    if (guests.length === 0) return
    setSubmitAttempted(true)
    if (!isSettingsValid) return
    const normalized: IGuestInput[] = guests.map((g) => {
      const profile = perGuestProfile
        ? { firstName: g.firstName, lastName: g.lastName, company: g.company }
        : { firstName: '', lastName: '', company: '' }
      const role = perGuestRole
        ? {
            m365GroupRole: g.m365GroupRole ?? 'Visitor',
            spGroupAction: g.spGroupAction ?? 'None',
            spGroupName: g.spGroupAction && g.spGroupAction !== 'None' ? g.spGroupName : undefined,
            spPermissionLevel:
              g.spGroupAction === 'CreateNew' ? (g.spPermissionLevel ?? 'Read') : undefined
          }
        : {
            m365GroupRole: sharedM365GroupRole,
            spGroupAction: sharedSpGroupAction,
            spGroupName: sharedSpGroupAction !== 'None' ? sharedSpGroupName : undefined,
            spPermissionLevel:
              sharedSpGroupAction === 'CreateNew' ? sharedSpPermissionLevel : undefined
          }
      return { ...g, ...profile, ...role }
    })
    setSubmitting(true)
    try {
      await ctx.invite(normalized)
    } finally {
      setSubmitting(false)
    }
  }, [
    guests,
    isSettingsValid,
    perGuestProfile,
    perGuestRole,
    sharedM365GroupRole,
    sharedSpGroupAction,
    sharedSpGroupName,
    sharedSpPermissionLevel,
    ctx
  ])

  const cancel = React.useCallback(() => onOpenChange(false), [onOpenChange])

  const submitDisabled = guests.length === 0 || submitting || loadingContext

  return {
    guests,
    addGuest,
    removeGuest,
    updateGuest,
    activeGuestEmail,
    setActiveGuestEmail,
    activeGuest,
    siteGroups,
    loadingContext,
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
    setSharedSpGroupAction: onSharedSpGroupActionChange,
    setSharedSpGroupName,
    setSharedSpPermissionLevel,
    submitting,
    submitDisabled,
    submit,
    cancel
  }
}
