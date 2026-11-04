import { type IAccessSnapshot, type IAccessTarget, RoleKind } from '../../models/IExternalParties'
import {
  accessForPrincipal,
  brokenTargetsWithoutPrincipal,
  effectiveAssignments,
  strongestRole,
  summarizeAccess,
  toRoleAssignments,
  webRoleForPrincipal
} from './accessModel'

const OWNERS = 3
const MEMBERS = 4
const EPL = 10
const PARTY = 20

const ra = (principalId: number, kind: RoleKind, name = RoleKind[kind]) => ({
  principalId,
  principalTitle: `P${principalId}`,
  principalType: 8,
  roles: [{ kind, name }]
})

const lib = (key: string, unique: boolean, isProtected = false): IAccessTarget => ({
  key,
  kind: 'library',
  listId: key,
  listTitle: key,
  listUrl: key,
  title: key,
  hasUniqueRoleAssignments: unique,
  isProtected
})

const folder = (parent: string, name: string, unique: boolean): IAccessTarget => ({
  key: `${parent}/${name}`,
  kind: 'folder',
  listId: parent,
  listTitle: parent,
  listUrl: parent,
  itemId: 1,
  title: `${parent} / ${name}`,
  name,
  hasUniqueRoleAssignments: unique,
  isProtected: false,
  parentKey: parent
})

const snapshot: IAccessSnapshot = {
  targets: [
    lib('Dokumenter', false),
    folder('Dokumenter', '01 Tegninger', true),
    folder('Dokumenter', '02 Kontrakt', false),
    lib('LevA', true),
    folder('LevA', '01 Grunnlag', false),
    lib('Interne', true, true)
  ],
  assignments: {
    'Dokumenter/01 Tegninger': [
      ra(OWNERS, RoleKind.Administrator),
      ra(EPL, RoleKind.Reader),
      ra(PARTY, RoleKind.Contributor)
    ],
    LevA: [
      ra(OWNERS, RoleKind.Administrator),
      ra(MEMBERS, RoleKind.Editor),
      ra(PARTY, RoleKind.Contributor)
    ],
    Interne: [ra(OWNERS, RoleKind.Administrator)]
  },
  webAssignments: [
    ra(OWNERS, RoleKind.Administrator),
    ra(MEMBERS, RoleKind.Editor),
    ra(EPL, RoleKind.Reader)
  ]
}

describe('toRoleAssignments', () => {
  it('drops hidden roles and principals left without roles', () => {
    const result = toRoleAssignments([
      {
        PrincipalId: 1,
        Member: { Title: 'Gjest', PrincipalType: 1 },
        RoleDefinitionBindings: [{ Name: 'Begrenset tilgang', RoleTypeKind: 1, Hidden: true }]
      },
      {
        PrincipalId: 2,
        Member: { Title: 'Leverandør A', PrincipalType: 8 },
        RoleDefinitionBindings: [
          { Name: 'Begrenset tilgang', RoleTypeKind: 1, Hidden: true },
          { Name: 'Bidra', RoleTypeKind: 3, Hidden: false }
        ]
      }
    ])
    expect(result).toEqual([
      {
        principalId: 2,
        principalTitle: 'Leverandør A',
        principalType: 8,
        roles: [{ name: 'Bidra', kind: RoleKind.Contributor }]
      }
    ])
  })
})

describe('strongestRole', () => {
  it('picks the strongest role and returns None for an empty list', () => {
    expect(
      strongestRole([
        { kind: RoleKind.Reader, name: 'Lese' },
        { kind: RoleKind.Editor, name: 'Rediger' },
        { kind: RoleKind.Contributor, name: 'Bidra' }
      ]).kind
    ).toBe(RoleKind.Editor)
    expect(strongestRole([]).kind).toBe(RoleKind.None)
  })
})

describe('effectiveAssignments', () => {
  it('uses own assignments, then the parent library, then the web', () => {
    const [docs, tegninger, kontrakt, levA, grunnlag] = snapshot.targets
    expect(effectiveAssignments(snapshot, tegninger)).toBe(
      snapshot.assignments['Dokumenter/01 Tegninger']
    )
    expect(effectiveAssignments(snapshot, grunnlag)).toBe(snapshot.assignments.LevA)
    expect(effectiveAssignments(snapshot, kontrakt)).toBe(snapshot.webAssignments)
    expect(effectiveAssignments(snapshot, docs)).toBe(snapshot.webAssignments)
    expect(effectiveAssignments(snapshot, levA)).toBe(snapshot.assignments.LevA)
  })
})

describe('accessForPrincipal', () => {
  it('lists direct access on targets with unique role assignments only', () => {
    const access = accessForPrincipal(snapshot, PARTY)
    expect(access.map((a) => [a.target.key, a.role])).toEqual([
      ['Dokumenter/01 Tegninger', RoleKind.Contributor],
      ['LevA', RoleKind.Contributor]
    ])
    const summary = summarizeAccess(access)
    expect(summary.libraries.map((a) => a.target.key)).toEqual(['LevA'])
    expect(summary.folders.map((a) => a.target.key)).toEqual(['Dokumenter/01 Tegninger'])
  })

  it('reports the web role and where a principal is missing', () => {
    expect(webRoleForPrincipal(snapshot, EPL).kind).toBe(RoleKind.Reader)
    expect(webRoleForPrincipal(snapshot, PARTY).kind).toBe(RoleKind.None)
    expect(brokenTargetsWithoutPrincipal(snapshot, EPL).map((t) => t.key)).toEqual([
      'LevA',
      'Interne'
    ])
  })
})
