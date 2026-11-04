import { groupPermissionNames, type ISiteGroup } from '../../../../services/SiteService'
import { buildGroupOptions, groupDisplayName } from './groupOptions'

const SITE = 'Landstrømanlegg Risavika Nord'
const g = (Id: number, Title: string, Description = '', PermissionLevel?: string): ISiteGroup => ({
  Id,
  Title,
  LoginName: Title,
  Description,
  PermissionLevel
})

const groups = [
  g(1, `${SITE} – Elkompaniet`, 'Samarbeidspart: Leverandør. Opprettet med Samarbeidsparter.'),
  g(2, `${SITE} – Ekstern prosjektleder`, 'Ekstern prosjektleder.', 'Lese'),
  g(3, `${SITE} – Deloitte`, 'Samarbeidspart: Konsulent.'),
  g(4, `${SITE} Owners`, '', 'Full kontroll'),
  g(5, `${SITE} – Evaluering`, '')
]

describe('buildGroupOptions', () => {
  it('puts fixed roles first, then partners with their type, then other groups', () => {
    const sections = buildGroupOptions(groups, SITE, 'Ekstern prosjektleder')
    expect(sections.map((s) => s.key)).toEqual(['fixed', 'parties', 'other'])
    expect(sections[0].options.map((o) => [o.displayName, o.secondary])).toEqual([
      ['Ekstern prosjektleder', 'Lese']
    ])
    expect(sections[1].options.map((o) => [o.displayName, o.secondary])).toEqual([
      ['Deloitte', 'Konsulent'],
      ['Elkompaniet', 'Leverandør']
    ])
    // Only the «<site> – » prefix is removed; standard groups keep their name.
    expect(sections[2].options.map((o) => o.displayName)).toEqual(['Evaluering', `${SITE} Owners`])
  })

  it('gives one section with short names on a site without partners or fixed roles', () => {
    const plain = [g(4, `${SITE} Owners`, '', 'Full kontroll'), g(5, `${SITE} – Evaluering`)]
    const sections = buildGroupOptions(plain, SITE, '')
    expect(sections.map((s) => s.key)).toEqual(['other'])
    expect(groupDisplayName(sections, `${SITE} – Evaluering`)).toBe('Evaluering')
    expect(groupDisplayName(sections, 'Ukjent')).toBe('Ukjent')
  })

  it('keeps full names when the site title is unknown', () => {
    const sections = buildGroupOptions(groups, undefined, undefined)
    expect(sections.map((s) => s.key)).toEqual(['parties', 'other'])
    expect(sections[0].options[0].displayName).toBe(`${SITE} – Deloitte`)
  })
})

describe('groupPermissionNames', () => {
  it('drops Limited Access in any language', () => {
    expect(
      groupPermissionNames([
        { Name: 'Begrenset tilgang', Hidden: true, RoleTypeKind: 1 },
        { Name: 'Lese', Hidden: false, RoleTypeKind: 2 }
      ])
    ).toBe('Lese')
    expect(groupPermissionNames([{ Name: 'Begrenset tilgang', RoleTypeKind: 1 }])).toBe('')
    expect(groupPermissionNames([{ Name: 'Limited Access' }])).toBe('')
  })
})
