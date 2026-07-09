import * as React from 'react'

import * as strings from 'ProvisionWebPartsStrings'
import { useInviteGuestsContext } from '../context'
import type {
  FeatureToggleMode,
  IGuestInput,
  M365GroupRole,
  SPGroupAction,
  SPGroupActionUI,
  SPPermissionLevel
} from '../../../models/IGuestRequest'
import type { ISiteGroup } from '../../../services'
import { isValidEmail } from '../../../utils'

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
  isGroupConnected: boolean

  spActionOptions: SPGroupActionUI[]

  perGuestProfile: boolean
  setUserPerGuestProfile: (value: boolean) => void
  perGuestRole: boolean
  setUserPerGuestRole: (value: boolean) => void

  sharedM365GroupRole: M365GroupRole
  setSharedM365GroupRole: (role: M365GroupRole) => void

  sharedSpGroupAction: SPGroupActionUI
  sharedSpGroupName: string | undefined
  sharedSpPermissionLevel: SPPermissionLevel | undefined
  sharedSpGroupNameValidationMessage: string | undefined
  setSharedSpGroupAction: (action: SPGroupActionUI) => void
  setSharedSpGroupName: (name: string | undefined) => void
  setSharedSpPermissionLevel: (level: SPPermissionLevel) => void

  submitting: boolean
  submitDisabled: boolean
  submit: () => Promise<void>
  cancel: () => void
}

const resolveToggle = (mode: FeatureToggleMode, userValue: boolean): boolean => {
  if (mode === 'Enforced') return true
  if (mode === 'Disabled') return false
  return userValue
}

const DEFAULT_SP_ACTION_ORDER: SPGroupActionUI[] = ['None', 'AddToExisting', 'CreateNew', 'Preset']

/**
 * Builds the ordered, visible list of SP-group action radios from the admin
 * config: toggles control visibility, the CSV order controls sequence (unlisted
 * actions fall back to default order after the listed ones). Preset additionally
 * requires a configured group name. Falls back to ['None'] if everything is off
 * so the section is never an empty radio group.
 */
const computeSpActionOptions = (
  visibility: Record<SPGroupActionUI, boolean>,
  orderCsv: string
): SPGroupActionUI[] => {
  const parsed = (orderCsv || '')
    .split(/[,;\n]+/)
    .map((s) => s.trim())
    .filter((s): s is SPGroupActionUI => (DEFAULT_SP_ACTION_ORDER as string[]).indexOf(s) !== -1)
  const deduped = parsed.filter((k, i) => parsed.indexOf(k) === i)
  const ordered = [...deduped, ...DEFAULT_SP_ACTION_ORDER.filter((k) => deduped.indexOf(k) === -1)]
  const visible = ordered.filter((k) => visibility[k])
  return visible.length > 0 ? visible : ['None']
}

interface ISharedSettings {
  m365GroupRole: M365GroupRole
  spGroupAction: SPGroupActionUI
  spGroupName: string | undefined
  spPermissionLevel: SPPermissionLevel | undefined
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
  const [isGroupConnected, setIsGroupConnected] = React.useState(false)

  const [userPerGuestProfile, setUserPerGuestProfile] = React.useState(false)
  const [userPerGuestRole, setUserPerGuestRole] = React.useState(false)
  const perGuestProfile = resolveToggle(ctx.perGuestProfileMode, userPerGuestProfile)
  const perGuestRole = resolveToggle(ctx.perGuestRoleMode, userPerGuestRole)

  const spActionOptions = React.useMemo<SPGroupActionUI[]>(
    () =>
      computeSpActionOptions(
        {
          None: ctx.showSpActionNone,
          AddToExisting: ctx.showSpActionAddToExisting,
          CreateNew: ctx.showSpActionCreateNew,
          Preset: ctx.showSpActionPreset && !!ctx.presetSpGroupName
        },
        ctx.spGroupActionOrder
      ),
    [
      ctx.showSpActionNone,
      ctx.showSpActionAddToExisting,
      ctx.showSpActionCreateNew,
      ctx.showSpActionPreset,
      ctx.presetSpGroupName,
      ctx.spGroupActionOrder
    ]
  )
  const firstVisibleAction = spActionOptions[0]

  const initialShared = React.useMemo<ISharedSettings>(() => {
    // If the configured default action was hidden by the toggles, fall back to
    // the first visible option so the radio group always shows a valid selection.
    const action: SPGroupActionUI =
      spActionOptions.indexOf(ctx.defaultSpGroupAction) !== -1
        ? ctx.defaultSpGroupAction
        : firstVisibleAction
    const spGroupName =
      action === 'Preset'
        ? ctx.presetSpGroupName
        : ctx.defaultSpGroupName
          ? ctx.defaultSpGroupName
          : undefined
    return {
      m365GroupRole: ctx.defaultM365GroupRole,
      spGroupAction: action,
      spGroupName,
      spPermissionLevel: ctx.defaultSpPermissionLevel
    }
  }, [
    ctx.defaultM365GroupRole,
    ctx.defaultSpGroupAction,
    ctx.defaultSpGroupName,
    ctx.presetSpGroupName,
    ctx.defaultSpPermissionLevel,
    spActionOptions,
    firstVisibleAction
  ])

  const [shared, setShared] = React.useState<ISharedSettings>(initialShared)

  React.useEffect(() => {
    if (!open) {
      setGuests([])
      setActiveGuestEmail(undefined)
      setUserPerGuestProfile(false)
      setUserPerGuestRole(false)
      setShared(initialShared)
      setSubmitAttempted(false)
      return
    }
    let cancelled = false
    setLoadingContext(true)
    void (async () => {
      try {
        const hiddenTerms = ctx.hiddenSpGroups
          ? ctx.hiddenSpGroups
              .split(/[,;\n]+/)
              .map((s) => s.trim())
              .filter(Boolean)
          : []
        const allowedTerms = ctx.allowedSpGroups
          ? ctx.allowedSpGroups
              .split(/[,;\n]+/)
              .map((s) => s.trim())
              .filter(Boolean)
          : []
        const [siteContext, groups] = await Promise.all([
          ctx.siteService.getSiteContext(),
          ctx.siteService.getSiteGroups(hiddenTerms, allowedTerms)
        ])
        if (cancelled) return
        setSiteGroups(groups)
        setIsGroupConnected(siteContext.isGroupConnected)
        // Explicit defaultSpGroupName takes precedence; otherwise fall back to
        // the site's Visitors group when auto-select is on.
        if (
          ctx.defaultSpGroupAction === 'AddToExisting' &&
          !ctx.defaultSpGroupName &&
          ctx.autoSelectVisitorGroup &&
          siteContext.associatedVisitorGroupTitle
        ) {
          setShared((prev) => ({
            ...prev,
            spGroupName: siteContext.associatedVisitorGroupTitle
          }))
        }
      } finally {
        if (!cancelled) setLoadingContext(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [
    open,
    ctx.siteService,
    ctx.autoSelectVisitorGroup,
    ctx.defaultSpGroupAction,
    ctx.defaultSpGroupName,
    ctx.hiddenSpGroups,
    ctx.allowedSpGroups,
    initialShared
  ])

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
        loading: true,
        // Seed per-guest action with the first visible option so the stored
        // value matches the radio shown (and the default isn't a hidden action).
        spGroupAction: firstVisibleAction,
        spGroupName: firstVisibleAction === 'Preset' ? ctx.presetSpGroupName : undefined
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
    [ctx.graphService, ctx.presetSpGroupName, firstVisibleAction]
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

  const setSharedM365GroupRole = React.useCallback((m365GroupRole: M365GroupRole) => {
    setShared((prev) => ({ ...prev, m365GroupRole }))
  }, [])

  const setSharedSpGroupAction = React.useCallback(
    (spGroupAction: SPGroupActionUI) => {
      // Preset uses the admin-configured group name (no dropdown); other actions
      // reset the name so the user picks/enters it.
      setShared((prev) => ({
        ...prev,
        spGroupAction,
        spGroupName: spGroupAction === 'Preset' ? ctx.presetSpGroupName : undefined
      }))
      setSubmitAttempted(false)
    },
    [ctx.presetSpGroupName]
  )

  const setSharedSpGroupName = React.useCallback((spGroupName: string | undefined) => {
    setShared((prev) => ({ ...prev, spGroupName }))
  }, [])

  const setSharedSpPermissionLevel = React.useCallback((spPermissionLevel: SPPermissionLevel) => {
    setShared((prev) => ({ ...prev, spPermissionLevel }))
  }, [])

  const sharedSpGroupNameValidationMessage = React.useMemo(() => {
    if (!submitAttempted) return undefined
    if (perGuestRole) return undefined
    if (shared.spGroupAction === 'None') return undefined
    if (!shared.spGroupName || !shared.spGroupName.trim()) return strings.SPGroupNewNameRequired
    return undefined
  }, [submitAttempted, perGuestRole, shared.spGroupAction, shared.spGroupName])

  const isSettingsValid = React.useMemo(() => {
    if (perGuestRole) {
      return guests.every((g) => {
        const action = g.spGroupAction ?? 'None'
        if (action === 'None') return true
        return !!g.spGroupName && g.spGroupName.trim().length > 0
      })
    }
    if (shared.spGroupAction === 'None') return true
    return !!shared.spGroupName && shared.spGroupName.trim().length > 0
  }, [perGuestRole, guests, shared.spGroupAction, shared.spGroupName])

  const submit = React.useCallback(async (): Promise<void> => {
    if (guests.length === 0) return
    setSubmitAttempted(true)
    if (!isSettingsValid) return
    const normalized: IGuestInput[] = guests.map((g) => {
      const profile = perGuestProfile
        ? { firstName: g.firstName, lastName: g.lastName, company: g.company }
        : { firstName: '', lastName: '', company: '' }
      // Preset is a UI-only action — normalize to AddToExisting so persisted
      // data only holds None/AddToExisting/CreateNew (matches the list CHOICE).
      const normalizeAction = (a: SPGroupActionUI | undefined): SPGroupAction =>
        a === 'Preset' ? 'AddToExisting' : (a ?? 'None')
      const role = perGuestRole
        ? {
            m365GroupRole: g.m365GroupRole ?? 'Visitor',
            spGroupAction: normalizeAction(g.spGroupAction),
            spGroupName: g.spGroupAction && g.spGroupAction !== 'None' ? g.spGroupName : undefined,
            spPermissionLevel:
              g.spGroupAction === 'CreateNew' ? (g.spPermissionLevel ?? 'Read') : undefined
          }
        : {
            m365GroupRole: shared.m365GroupRole,
            spGroupAction: normalizeAction(shared.spGroupAction),
            spGroupName: shared.spGroupAction !== 'None' ? shared.spGroupName : undefined,
            spPermissionLevel:
              shared.spGroupAction === 'CreateNew' ? shared.spPermissionLevel : undefined
          }
      return { ...g, ...profile, ...role }
    })
    setSubmitting(true)
    try {
      await ctx.invite(normalized)
    } finally {
      setSubmitting(false)
    }
  }, [guests, isSettingsValid, perGuestProfile, perGuestRole, shared, ctx])

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
    isGroupConnected,
    spActionOptions,
    perGuestProfile,
    setUserPerGuestProfile,
    perGuestRole,
    setUserPerGuestRole,
    sharedM365GroupRole: shared.m365GroupRole,
    setSharedM365GroupRole,
    sharedSpGroupAction: shared.spGroupAction,
    sharedSpGroupName: shared.spGroupName,
    sharedSpPermissionLevel: shared.spPermissionLevel,
    sharedSpGroupNameValidationMessage,
    setSharedSpGroupAction,
    setSharedSpGroupName,
    setSharedSpPermissionLevel,
    submitting,
    submitDisabled,
    submit,
    cancel
  }
}
