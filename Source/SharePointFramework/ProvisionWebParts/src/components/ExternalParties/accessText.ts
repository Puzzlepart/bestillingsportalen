import * as strings from 'ProvisionWebPartsStrings'

import { format } from '../../utils/format'
import type { IPartyRow } from './types'

const count = (n: number, one: string, many: string): string => (n === 1 ? one : format(many, n))

/**
 * Short text for the "Tilgang i dag" column, e.g. primary "Eget bibliotek"
 * and secondary "+ 3 mapper".
 */
export const accessText = (row: IPartyRow): { primary: string; secondary?: string } => {
  const otherLibraries = row.access.filter(
    (a) => a.target.kind === 'library' && a !== row.ownLibrary
  ).length
  const folders = row.access.filter((a) => a.target.kind === 'folder').length

  const rest = [
    otherLibraries > 0
      ? count(
          otherLibraries,
          strings.Parties.AccessLibrariesOne,
          strings.Parties.AccessLibrariesMany
        )
      : '',
    folders > 0
      ? count(folders, strings.Parties.AccessFoldersOne, strings.Parties.AccessFoldersMany)
      : ''
  ].filter(Boolean)

  if (row.ownLibrary) {
    return {
      primary: strings.Parties.AccessOwnLibrary,
      secondary: rest.length ? `+ ${rest.join(' · ')}` : undefined
    }
  }
  if (rest.length) return { primary: rest.join(' · ') }
  return { primary: strings.Parties.AccessNone }
}

export const membersText = (n: number): string =>
  count(n, strings.Parties.MembersOne, strings.Parties.MembersMany)
