/**
 * Parties are recognised by a marker at the start of the SharePoint group
 * description: "Samarbeidspart: <type>." The same marker is used by the
 * PowerShell prototype (New-Samarbeidspart.ps1), so groups created by either
 * are found by both.
 */
export const PARTY_MARKER_PREFIX = 'Samarbeidspart: '

/** Builds the group description for a new party. */
export const buildPartyDescription = (typeLabel: string, extra?: string): string =>
  `${PARTY_MARKER_PREFIX}${typeLabel}.${extra ? ` ${extra}` : ''}`

/**
 * Returns the party type label from a group description, or undefined when
 * the description does not carry the party marker.
 */
export const parsePartyType = (description: string | undefined): string | undefined => {
  if (!description || !description.startsWith(PARTY_MARKER_PREFIX)) return undefined
  const rest = description.substring(PARTY_MARKER_PREFIX.length)
  const type = rest.split('.')[0].trim()
  return type || undefined
}
