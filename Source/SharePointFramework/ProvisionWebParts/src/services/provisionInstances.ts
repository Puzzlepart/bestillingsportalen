/* eslint-disable no-console */

// Type-only import keeps this module free of runtime dependencies (so it is
// unit-testable under jest, where @pnp/sp ships untranspiled ESM). Callers
// must have imported '@pnp/sp/webs' for `sp.web.getStorageEntity` to exist —
// both web parts already do.
import type { SPFI } from '@pnp/sp'

/**
 * Tenant-wide storage entity holding the Bestillingsportalen instance
 * registry. The value is either a plain URL string (one instance) or a JSON
 * array of `{ title, url }` objects, where the FIRST entry is the tenant
 * default. Maintained by deploy.ps1, but can also be administered manually
 * with `Set-PnPStorageEntity` against the tenant app catalog.
 */
export const PROVISION_URLS_STORAGE_ENTITY_KEY = 'bp_ProvisionUrls'

/**
 * The solution's conventional default site URL, used when neither the web
 * part property nor the tenant registry provides one.
 */
export const DEFAULT_PROVISION_URL = '/sites/bestillingsportalen'

const RAW_ENTITY_CACHE_KEY = 'bp_provisionUrls'
const SELECTED_INSTANCE_STORAGE_KEY = 'bp_selectedProvisionUrl'

export interface IProvisionInstance {
  title: string
  url: string
}

const normalizeUrl = (url: string): string => url.trim().replace(/\/+$/, '')

/**
 * Parses a raw `bp_ProvisionUrls` storage entity value into instances.
 * Accepts a plain URL string (single instance titled "Bestillingsportalen")
 * or a JSON array of `{ title, url }` (keys matched case-insensitively).
 * Entries without a URL are dropped, duplicates (by lowercased normalized
 * URL) are removed, and a missing title falls back to the URL. Never throws.
 */
export function parseProvisionInstances(rawValue: string | undefined): IProvisionInstance[] {
  const raw = (rawValue ?? '').trim()
  if (!raw) return []

  let entries: any[]
  if (raw.startsWith('[')) {
    try {
      const parsed = JSON.parse(raw)
      entries = Array.isArray(parsed) ? parsed : []
    } catch (error) {
      console.warn(`Failed to parse ${PROVISION_URLS_STORAGE_ENTITY_KEY} storage entity:`, error)
      return []
    }
  } else {
    entries = [{ title: 'Bestillingsportalen', url: raw }]
  }

  const seen = new Set<string>()
  const instances: IProvisionInstance[] = []
  for (const entry of entries) {
    if (!entry || typeof entry !== 'object') continue
    const url = normalizeUrl(String(entry.url ?? entry.Url ?? ''))
    if (!url) continue
    const key = url.toLowerCase()
    if (seen.has(key)) continue
    seen.add(key)
    const title = String(entry.title ?? entry.Title ?? '').trim() || url
    instances.push({ title, url })
  }
  return instances
}

/**
 * Reads the tenant instance registry. `getStorageEntity` is readable for all
 * users from any web, regardless of app catalog permissions. The raw entity
 * value is cached in sessionStorage for the tab session ('' = not set), so
 * registry changes are picked up in a new tab/session. Never throws — any
 * error yields an empty registry.
 */
export async function getTenantProvisionInstances(sp: SPFI): Promise<IProvisionInstance[]> {
  let cached: string | undefined
  try {
    cached = sessionStorage.getItem(RAW_ENTITY_CACHE_KEY) ?? undefined
  } catch {
    /* sessionStorage unavailable (privacy mode etc.) — fall through to a fetch */
  }
  if (cached !== undefined) return parseProvisionInstances(cached)

  let raw = ''
  try {
    const entity = await sp.web.getStorageEntity(PROVISION_URLS_STORAGE_ENTITY_KEY)
    raw = entity?.Value ?? ''
  } catch (error) {
    console.warn(`Failed to read ${PROVISION_URLS_STORAGE_ENTITY_KEY} storage entity:`, error)
  }
  try {
    sessionStorage.setItem(RAW_ENTITY_CACHE_KEY, raw)
  } catch {
    /* best effort — a failed cache write just means an extra request next time */
  }
  return parseProvisionInstances(raw)
}

/**
 * The tenant default provisioning site URL: the registry's first instance,
 * or undefined when no registry is configured.
 */
export async function getTenantDefaultProvisionUrl(sp: SPFI): Promise<string | undefined> {
  const instances = await getTenantProvisionInstances(sp)
  return instances[0]?.url
}

/**
 * Resolves the effective provisioning site URL for the 0/1-instance cases.
 * On SharePoint pages the property-pane value wins; in Teams (no property
 * pane) the tenant registry wins over the preconfigured default. The
 * multi-instance Teams flow goes through the instance picker instead.
 */
export function resolveProvisionUrl(
  propertyValue: string | undefined,
  instances: IProvisionInstance[],
  isTeamsContext: boolean
): string {
  const property = (propertyValue ?? '').trim()
  const registryDefault = instances[0]?.url
  if (isTeamsContext) {
    return registryDefault || property || DEFAULT_PROVISION_URL
  }
  return property || registryDefault || DEFAULT_PROVISION_URL
}

/**
 * The instance URL the user picked last time (Teams picker), or undefined.
 * Only honored when the URL is still among the user's accessible instances.
 */
export function getRememberedInstanceUrl(): string | undefined {
  try {
    return localStorage.getItem(SELECTED_INSTANCE_STORAGE_KEY) ?? undefined
  } catch {
    return undefined
  }
}

/**
 * Persists the user's instance choice for future sessions (best effort).
 */
export function rememberInstanceUrl(url: string): void {
  try {
    localStorage.setItem(SELECTED_INSTANCE_STORAGE_KEY, url)
  } catch {
    /* best effort — a failed write just means the picker is shown again */
  }
}

/**
 * Compares two instance URLs ignoring case and trailing slashes.
 */
export function sameInstanceUrl(a?: string, b?: string): boolean {
  if (!a || !b) return false
  return normalizeUrl(a).toLowerCase() === normalizeUrl(b).toLowerCase()
}
