import type { IPartyType } from '../../models/IExternalParties'

/**
 * Configuration of the Samarbeidsparter web part, resolved from the web part
 * properties. The defaults are neutral, so the web part works on any site.
 * A template sets the values for its own access model, e.g. a fixed role and
 * protected libraries.
 */
export interface IPartiesConfig {
  /** Prefix for group titles. `{sitename}` is replaced with the site title. */
  groupPrefix: string
  /** Name of the external project manager group, without the prefix. */
  externalProjectManager: string
  partTypes: IPartyType[]
  /** OData filter for the libraries that are shown and can be shared. */
  librariesFilter: string
  /** Libraries that can never be shared, by title or URL name. */
  protectedLibraries: string[]
  /** Quick launch heading where links to the parties' own libraries are added. */
  navigationHeading: string
  /** Site-relative URL of the activity log list. */
  activityLogUrl: string
  /** Title of the activity log list. */
  activityLogTitle: string
  /** Link to the page where guests are invited. */
  guestInvitationUrl: string
  /** Whether a party can be given access to the whole site in the tree. */
  allowSiteAccess: boolean
}

export const DEFAULT_GROUP_PREFIX = '{sitename} – '
/** No fixed role by default. A template sets it, e.g. «Ekstern prosjektleder». */
export const DEFAULT_EXTERNAL_PROJECT_MANAGER = ''
export const DEFAULT_LIBRARIES_FILTER =
  "(BaseTemplate eq 101 and IsCatalog eq false and IsApplicationList eq false) and (Title ne 'Form Templates' and Title ne 'Skjemamaler')"
/** No protected libraries by default. A template sets them, e.g. «Interne dokumenter». */
export const DEFAULT_PROTECTED_LIBRARIES = ''
export const DEFAULT_NAVIGATION_HEADING = 'Samarbeidsparter'
export const DEFAULT_ACTIVITY_LOG_URL = 'Lists/ActivityLog'
export const DEFAULT_ACTIVITY_LOG_TITLE = 'Aktivitetslogg'
/** No link to a guest invitation page by default. */
export const DEFAULT_GUEST_INVITATION_URL = ''

export const DEFAULT_PART_TYPES: IPartyType[] = [
  {
    key: 'konsulent',
    label: 'Konsulent',
    libraryTitle: 'Konsulent – {name}',
    libraryUrl: 'Kon{code}',
    folders: [],
    ownLibraryRole: 'Contributor'
  },
  {
    key: 'leverandor',
    label: 'Leverandør',
    libraryTitle: 'Leverandør – {name}',
    libraryUrl: 'Lev{code}',
    folders: [],
    ownLibraryRole: 'Contributor'
  },
  {
    key: 'intern',
    label: 'Intern',
    libraryTitle: 'Intern – {name}',
    libraryUrl: 'Int{code}',
    folders: [],
    ownLibraryRole: 'Contributor'
  }
]

/** Splits a list typed in the property pane on comma, semicolon or newline. */
export const splitList = (value: string | undefined): string[] =>
  (value || '')
    .split(/[,;\n]+/)
    .map((v) => v.trim())
    .filter(Boolean)

const isPartyRole = (value: unknown): value is 'Contributor' | 'Reader' =>
  value === 'Contributor' || value === 'Reader'

/**
 * Parses the partTypes JSON from the property pane. Invalid JSON or entries
 * without key and label fall back to the defaults, so a typo never breaks the
 * web part.
 */
export const parsePartTypes = (json: string | undefined): IPartyType[] => {
  if (!json || !json.trim()) return DEFAULT_PART_TYPES
  try {
    const parsed = JSON.parse(json)
    const list = Array.isArray(parsed) ? parsed : parsed?.partTypes
    if (!Array.isArray(list)) return DEFAULT_PART_TYPES
    const types = list
      .filter((t) => t && typeof t.key === 'string' && typeof t.label === 'string')
      .map(
        (t): IPartyType => ({
          key: t.key,
          label: t.label,
          libraryTitle: typeof t.libraryTitle === 'string' ? t.libraryTitle : `${t.label} – {name}`,
          libraryUrl: typeof t.libraryUrl === 'string' ? t.libraryUrl : '{code}',
          folders: Array.isArray(t.folders) ? t.folders.filter((f) => typeof f === 'string') : [],
          ownLibraryRole: isPartyRole(t.ownLibraryRole) ? t.ownLibraryRole : 'Contributor'
        })
      )
    return types.length > 0 ? types : DEFAULT_PART_TYPES
  } catch {
    return DEFAULT_PART_TYPES
  }
}

/** Replaces `{sitename}` in the group prefix with the site title. */
export const resolveGroupPrefix = (prefix: string | undefined, siteTitle: string): string =>
  (prefix ?? DEFAULT_GROUP_PREFIX).replace(/\{sitename\}/gi, siteTitle)

/** Removes the resolved group prefix from a group title, if present. */
export const stripGroupPrefix = (title: string, resolvedPrefix: string): string =>
  resolvedPrefix && title.toLowerCase().startsWith(resolvedPrefix.toLowerCase())
    ? title.substring(resolvedPrefix.length)
    : title

/** Joins a site-relative path to the web's server-relative URL. */
export const toServerRelativeUrl = (webServerRelativeUrl: string, path: string): string => {
  if (!path) return webServerRelativeUrl
  if (path.startsWith('/')) return path
  return `${webServerRelativeUrl.replace(/\/$/, '')}/${path.replace(/^\//, '')}`
}

/**
 * Link to the guest invitation page with the group chosen, e.g.
 * «/sites/x/SitePages/Inviter-gjester.aspx?inviteGroup=12». Inviter gjester
 * reads the parameter and opens the panel with the group selected.
 */
export const guestInvitationLink = (pageUrl: string, groupId?: number): string => {
  if (!pageUrl || groupId === undefined) return pageUrl
  const [path, hash] = pageUrl.split('#')
  const separator = path.includes('?') ? '&' : '?'
  return `${path}${separator}inviteGroup=${groupId}${hash !== undefined ? `#${hash}` : ''}`
}

/** Returns true when the library title or URL name is in the protected list. */
export const isProtectedLibrary = (
  title: string,
  serverRelativeUrl: string,
  protectedLibraries: string[]
): boolean => {
  const urlName = decodeURIComponent(serverRelativeUrl.split('/').pop() || '').toLowerCase()
  return protectedLibraries.some((p) => {
    const value = p.trim().toLowerCase()
    return value === title.toLowerCase() || value === urlName
  })
}

/** Web part properties that resolvePartiesConfig reads. */
export interface IPartiesProperties {
  groupPrefix?: string
  externalProjectManager?: string
  partTypes?: string
  librariesFilter?: string
  protectedLibraries?: string
  navigationHeading?: string
  activityLogUrl?: string
  guestInvitationUrl?: string
  allowSiteAccess?: boolean
}

/**
 * Resolves the web part properties to a configuration. A missing property
 * (undefined) gets the default. An empty value turns the feature off where
 * that makes sense: no fixed role, no protected libraries, no menu link and
 * no link to the guest invitation page.
 */
export const resolvePartiesConfig = (p: IPartiesProperties): IPartiesConfig => {
  const valueOr = (value: string | undefined, fallback: string): string =>
    value === undefined || value === null ? fallback : value.trim()
  const nonEmptyOr = (value: string | undefined, fallback: string): string =>
    value && value.trim() ? value.trim() : fallback
  return {
    // The prefix keeps its trailing space, so it is not trimmed.
    groupPrefix: p.groupPrefix || DEFAULT_GROUP_PREFIX,
    externalProjectManager: valueOr(p.externalProjectManager, DEFAULT_EXTERNAL_PROJECT_MANAGER),
    partTypes: parsePartTypes(p.partTypes),
    librariesFilter: nonEmptyOr(p.librariesFilter, DEFAULT_LIBRARIES_FILTER),
    protectedLibraries: splitList(valueOr(p.protectedLibraries, DEFAULT_PROTECTED_LIBRARIES)),
    navigationHeading: valueOr(p.navigationHeading, DEFAULT_NAVIGATION_HEADING),
    activityLogUrl: nonEmptyOr(p.activityLogUrl, DEFAULT_ACTIVITY_LOG_URL),
    activityLogTitle: DEFAULT_ACTIVITY_LOG_TITLE,
    guestInvitationUrl: valueOr(p.guestInvitationUrl, DEFAULT_GUEST_INVITATION_URL),
    allowSiteAccess: p.allowSiteAccess !== false
  }
}
