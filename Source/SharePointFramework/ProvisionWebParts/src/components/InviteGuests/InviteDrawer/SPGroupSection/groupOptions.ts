import type { ISiteGroup } from '../../../../services/SiteService'
import { parsePartyType } from '../../../../services/parties/partyMarker'
import {
  DEFAULT_GROUP_PREFIX,
  resolveGroupPrefix,
  splitList,
  stripGroupPrefix
} from '../../../../services/parties/partyConfig'

export type GroupSectionKey = 'fixed' | 'parties' | 'other'

export interface IGroupOption {
  group: ISiteGroup
  /** The name shown in the list: the group title without «<site title> – ». */
  displayName: string
  /** Party type for parties, otherwise the permission level, e.g. «Lese». */
  secondary?: string
}

export interface IGroupOptionSection {
  key: GroupSectionKey
  options: IGroupOption[]
}

/**
 * Splits the site groups into sections for the group picker: fixed roles
 * (e.g. Ekstern prosjektleder), partners (groups with the party marker from
 * Samarbeidsparter) and other groups. Names are shown without the site
 * prefix. Without fixed roles and partners there is one section, so sites
 * that do not use partners see one list as before.
 */
export const buildGroupOptions = (
  groups: ISiteGroup[],
  siteTitle: string | undefined,
  fixedRoleGroups: string | undefined
): IGroupOptionSection[] => {
  const prefix = siteTitle ? resolveGroupPrefix(DEFAULT_GROUP_PREFIX, siteTitle) : ''
  const fixedNames = splitList(fixedRoleGroups).map((n) => n.toLowerCase())
  const sections: Record<GroupSectionKey, IGroupOption[]> = { fixed: [], parties: [], other: [] }

  for (const group of groups) {
    const displayName = stripGroupPrefix(group.Title, prefix)
    const partyType = parsePartyType(group.Description)
    const isFixed =
      fixedNames.includes(displayName.toLowerCase()) ||
      fixedNames.includes(group.Title.toLowerCase())
    if (isFixed) {
      sections.fixed.push({ group, displayName, secondary: group.PermissionLevel })
    } else if (partyType) {
      sections.parties.push({ group, displayName, secondary: partyType })
    } else {
      sections.other.push({ group, displayName, secondary: group.PermissionLevel })
    }
  }

  const byName = (a: IGroupOption, b: IGroupOption): number =>
    a.displayName.localeCompare(b.displayName, 'nb')
  return (['fixed', 'parties', 'other'] as GroupSectionKey[])
    .map((key) => ({ key, options: sections[key].sort(byName) }))
    .filter((s) => s.options.length > 0)
}

/** The display name for a selected group title, or the title itself. */
export const groupDisplayName = (sections: IGroupOptionSection[], title: string): string => {
  for (const s of sections) {
    const match = s.options.find((o) => o.group.Title === title)
    if (match) return match.displayName
  }
  return title
}
