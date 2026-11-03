import type { IAccessSnapshot, IParty, IPartyType } from '../../models/IExternalParties'
import { accessForPrincipal, webRoleForPrincipal } from '../../services/parties/accessModel'
import { RoleKind } from '../../models/IExternalParties'
import type { IPartyRow, PartyStatus } from './types'

/** Title the party's own library gets from its type, e.g. "Leverandør – Leverandør A". */
export const ownLibraryTitle = (party: IParty, partTypes: IPartyType[]): string | undefined => {
  const type = partTypes.find((t) => t.label.toLowerCase() === party.type.toLowerCase())
  return type ? type.libraryTitle.replace(/\{name\}/gi, party.name) : undefined
}

export const partyStatus = (memberCount: number, hasAccess: boolean): PartyStatus => {
  if (memberCount === 0) return 'NoMembers'
  if (!hasAccess) return 'NoAccess'
  return 'OK'
}

/**
 * Builds the overview rows: one per party, with the libraries and first-level
 * folders the party has direct access to. The external project manager also
 * counts access on the site itself.
 */
export const buildPartyRows = (
  parties: IParty[],
  snapshot: IAccessSnapshot,
  partTypes: IPartyType[]
): IPartyRow[] =>
  parties.map((party) => {
    const access = accessForPrincipal(snapshot, party.id)
    const title = ownLibraryTitle(party, partTypes)?.toLowerCase()
    const ownLibrary = title
      ? access.find((a) => a.target.kind === 'library' && a.target.title.toLowerCase() === title)
      : undefined
    const hasWebAccess = webRoleForPrincipal(snapshot, party.id).kind !== RoleKind.None
    return {
      party,
      access,
      ownLibrary,
      status: partyStatus(party.memberCount, access.length > 0 || hasWebAccess)
    }
  })
