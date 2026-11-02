import type { IAccessSnapshot, IParty, IPrincipalAccess } from '../../models/IExternalParties'
import type {
  AccessReaderService,
  IPartiesConfig,
  IPartiesSiteInfo,
  PartiesService
} from '../../services/parties'

export interface IExternalPartiesProps {
  title: string
  description?: string
  config: IPartiesConfig
  partiesService: PartiesService
  accessReader: AccessReaderService
}

/** Status shown for a party in the overview. Based on facts only, never a blueprint. */
export type PartyStatus = 'OK' | 'NoMembers' | 'NoAccess' | 'Missing'

export interface IPartyRow {
  party: IParty
  access: IPrincipalAccess[]
  /** The party's own library, when one matches the party type's library title. */
  ownLibrary?: IPrincipalAccess
  status: PartyStatus
}

export interface IExternalPartiesData {
  site: IPartiesSiteInfo
  parties: IParty[]
  snapshot: IAccessSnapshot
  rows: IPartyRow[]
  /** The external project manager group, if it exists on the site. */
  externalProjectManager?: IParty
}

export type DrawerState = { kind: 'none' } | { kind: 'party'; partyId: number } | { kind: 'epl' }
