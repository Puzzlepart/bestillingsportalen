import type { IPartyType, PartyRole } from '../../models/IExternalParties'
import { buildPartyDescription } from './partyMarker'
import { resolveGroupPrefix } from './partyConfig'

export const PARTY_NAME_MAX_LENGTH = 60

/** Characters SharePoint does not accept in group names, same rule as New-Samarbeidspart.ps1. */
const FORBIDDEN_NAME_CHARACTERS = /["/\\[\]:|<>+=;,?*'@]/

/** 2–20 letters (a–z) and digits, starting with a letter. Becomes part of the library URL. */
const LIBRARY_CODE = /^[A-Za-z][A-Za-z0-9]{1,19}$/

export type PartyNameError = 'Required' | 'TooLong' | 'InvalidCharacters'
export type LibraryCodeError = 'Required' | 'Invalid'

export const validatePartyName = (name: string | undefined): PartyNameError | undefined => {
  const value = (name || '').trim()
  if (!value) return 'Required'
  if (value.length > PARTY_NAME_MAX_LENGTH) return 'TooLong'
  if (FORBIDDEN_NAME_CHARACTERS.test(value)) return 'InvalidCharacters'
  return undefined
}

export const validateLibraryCode = (code: string | undefined): LibraryCodeError | undefined => {
  const value = (code || '').trim()
  if (!value) return 'Required'
  return LIBRARY_CODE.test(value) ? undefined : 'Invalid'
}

/** Suggests a library code from the party name, e.g. "Rådgiver A" → "RadgiverA". */
export const suggestLibraryCode = (name: string | undefined): string => {
  const ascii = (name || '')
    .replace(/[æÆ]/g, (c) => (c === 'æ' ? 'ae' : 'Ae'))
    .replace(/[øØ]/g, (c) => (c === 'ø' ? 'o' : 'O'))
    .replace(/[åÅ]/g, (c) => (c === 'å' ? 'a' : 'A'))
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^A-Za-z0-9]/g, '')
  const code = ascii.replace(/^[0-9]+/, '').substring(0, 20)
  return code.length >= 2 ? code : ''
}

export interface INewPartyInput {
  name: string
  type: IPartyType
  /** Create the party's own library. */
  ownLibrary: boolean
  /** Library code, required with ownLibrary. */
  code?: string
}

export interface INewLibraryDefinition {
  title: string
  /** URL name of the library, e.g. "LevLevA". */
  urlName: string
  serverRelativeUrl: string
  description: string
  folders: string[]
  role: PartyRole
}

export interface INewPartyDefinition {
  name: string
  groupTitle: string
  groupDescription: string
  library?: INewLibraryDefinition
}

/**
 * Resolves the names of what is created for a new party. The rules are the
 * same as in New-Samarbeidspart.ps1, so parties created by the web part and by
 * the prototype look the same.
 */
export const defineNewParty = (
  input: INewPartyInput,
  siteTitle: string,
  webServerRelativeUrl: string,
  groupPrefix: string
): INewPartyDefinition => {
  const name = input.name.trim()
  const groupTitle = `${resolveGroupPrefix(groupPrefix, siteTitle)}${name}`
  const definition: INewPartyDefinition = {
    name,
    groupTitle,
    groupDescription: buildPartyDescription(input.type.label, 'Opprettet med Samarbeidsparter.')
  }
  if (input.ownLibrary) {
    const code = (input.code || '').trim()
    const urlName = input.type.libraryUrl.replace(/\{code\}/gi, code)
    definition.library = {
      title: input.type.libraryTitle.replace(/\{name\}/gi, name),
      urlName,
      serverRelativeUrl: `${webServerRelativeUrl.replace(/\/$/, '')}/${urlName}`,
      description: buildPartyDescription(input.type.label, `Eget bibliotek for ${groupTitle}.`),
      folders: input.type.folders,
      role: input.type.ownLibraryRole
    }
  }
  return definition
}

/**
 * Comparable form of a quick launch URL: server-relative, decoded, without a
 * trailing slash, lower case. Same rule as ConvertTo-TilgangsmodellNavUrl.
 */
export const normalizeNavUrl = (url: string | undefined): string => {
  let value = url || ''
  try {
    value = decodeURIComponent(value)
  } catch {
    // Keep the URL as is when it is not valid URI encoding.
  }
  return value
    .replace(/^https?:\/\/[^/]+/i, '')
    .replace(/\/+$/, '')
    .toLowerCase()
}

/** True for quick launch headings without a link. */
export const isLinklessHeading = (url: string | undefined): boolean =>
  /linkless\.header/i.test(url || '')

/**
 * Reads the message SharePoint returns in a PnPjs error, e.g. "Error making
 * HttpClient request in queryable [403] ::> {"odata.error":...}".
 */
export const errorMessage = (error: unknown): string => {
  const message = (error as Error)?.message || String(error)
  const json = message.indexOf('::>')
  if (json >= 0) {
    try {
      const parsed = JSON.parse(message.substring(json + 3).trim())
      const odata = parsed['odata.error'] || parsed.error
      const value = odata?.message?.value ?? odata?.message
      if (typeof value === 'string' && value) return value
    } catch {
      // Not JSON. Fall through to the full message.
    }
  }
  return message
}
