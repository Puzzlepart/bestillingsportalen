import { type IAccessSnapshot, type IAccessTarget, RoleKind } from '../../models/IExternalParties'
import { inheritedFrom, pruneInheritedDesired } from './accessModel'
import { currentDesiredAccess, planAccessChanges } from './accessPlanner'

const OWNERS = 3
const EPL = 10
const PARTY = 20

const ra = (principalId: number, kind: RoleKind) => ({
  principalId,
  principalTitle: `P${principalId}`,
  principalType: 8,
  roles: [{ kind, name: RoleKind[kind] }]
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

const build = (webHasEpl: boolean): IAccessSnapshot => ({
  targets: [
    lib('Dokumenter', false),
    folder('Dokumenter', '01 Tegninger', true),
    folder('Dokumenter', '02 Kontrakt', false),
    lib('LevA', true),
    lib('Interne', true, true)
  ],
  assignments: {
    'Dokumenter/01 Tegninger': [ra(OWNERS, RoleKind.Administrator), ra(PARTY, RoleKind.Reader)],
    LevA: [
      ra(OWNERS, RoleKind.Administrator),
      ra(EPL, RoleKind.Reader),
      ra(PARTY, RoleKind.Editor)
    ],
    Interne: [ra(OWNERS, RoleKind.Administrator)]
  },
  webAssignments: webHasEpl
    ? [ra(OWNERS, RoleKind.Administrator), ra(EPL, RoleKind.Reader)]
    : [ra(OWNERS, RoleKind.Administrator)]
})

const stepTypes = (steps: { type: string; target: IAccessTarget }[]) =>
  steps.map((s) => `${s.type}:${s.target.key}`)

describe('currentDesiredAccess', () => {
  it('maps today’s access to party roles and shows stronger roles as Contributor', () => {
    expect(currentDesiredAccess(build(true), PARTY)).toEqual({
      'Dokumenter/01 Tegninger': 'Reader',
      LevA: 'Contributor'
    })
  })
})

describe('planAccessChanges', () => {
  it('changes only targets where the role differs', () => {
    const snapshot = build(true)
    const plan = planAccessChanges({
      snapshot,
      partyId: PARTY,
      externalProjectManagerId: EPL,
      desired: { 'Dokumenter/01 Tegninger': 'Reader', LevA: 'Contributor' }
    })
    // LevA is Editor today, which differs from Contributor and is changed.
    expect(plan.changes.map((c) => [c.kind, c.target.key])).toEqual([['change', 'LevA']])
    expect(plan.rejected).toEqual([])
  })

  it('breaks inheritance before adding and keeps the EPL from the web', () => {
    const plan = planAccessChanges({
      snapshot: build(true),
      partyId: PARTY,
      externalProjectManagerId: EPL,
      desired: {
        'Dokumenter/01 Tegninger': 'Reader',
        LevA: 'Contributor',
        'Dokumenter/02 Kontrakt': 'Contributor'
      }
    })
    const add = plan.changes.find((c) => c.kind === 'add')
    expect(add.target.key).toBe('Dokumenter/02 Kontrakt')
    expect(add.breaksInheritance).toBe(true)
    expect(stepTypes(plan.steps)).toEqual([
      'breakInheritance:Dokumenter/02 Kontrakt',
      'add:Dokumenter/02 Kontrakt',
      'change:LevA'
    ])
  })

  it('gives the EPL access where it would be missing after the change', () => {
    const plan = planAccessChanges({
      snapshot: build(false),
      partyId: PARTY,
      externalProjectManagerId: EPL,
      desired: { 'Dokumenter/02 Kontrakt': 'Reader', 'Dokumenter/01 Tegninger': 'Reader' }
    })
    expect(stepTypes(plan.steps)).toEqual([
      'breakInheritance:Dokumenter/02 Kontrakt',
      'add:Dokumenter/02 Kontrakt',
      'ensureExternalProjectManager:Dokumenter/02 Kontrakt',
      'remove:LevA'
    ])
  })

  it('does not add an EPL step when there is no EPL group', () => {
    const plan = planAccessChanges({
      snapshot: build(false),
      partyId: PARTY,
      desired: { Dokumenter: 'Reader' }
    })
    expect(plan.steps.map((s) => s.type)).not.toContain('ensureExternalProjectManager')
  })

  it('adds to a target with unique access without breaking inheritance', () => {
    const plan = planAccessChanges({
      snapshot: build(true),
      partyId: 99,
      externalProjectManagerId: EPL,
      desired: { LevA: 'Reader' }
    })
    expect(plan.changes).toEqual([
      expect.objectContaining({ kind: 'add', role: 'Reader', breaksInheritance: false })
    ])
    expect(stepTypes(plan.steps)).toEqual(['add:LevA'])
  })

  it('changes the role and removes access that is no longer wanted', () => {
    const plan = planAccessChanges({
      snapshot: build(true),
      partyId: PARTY,
      externalProjectManagerId: EPL,
      desired: { 'Dokumenter/01 Tegninger': 'Contributor' }
    })
    expect(plan.changes.map((c) => [c.kind, c.target.key, c.role, c.from])).toEqual([
      ['change', 'Dokumenter/01 Tegninger', 'Contributor', RoleKind.Reader],
      ['remove', 'LevA', undefined, RoleKind.Editor]
    ])
  })

  it('rejects protected and unknown targets', () => {
    const plan = planAccessChanges({
      snapshot: build(true),
      partyId: PARTY,
      externalProjectManagerId: EPL,
      desired: {
        'Dokumenter/01 Tegninger': 'Reader',
        LevA: 'Contributor',
        Interne: 'Reader',
        Ukjent: 'Reader'
      }
    })
    expect(plan.rejected.sort()).toEqual(['Interne', 'Ukjent'])
    expect(plan.steps.some((s) => s.target.key === 'Interne')).toBe(false)
  })
})

describe('site access and inheritance', () => {
  const web: IAccessTarget = {
    key: '/sites/k',
    kind: 'web',
    listId: '',
    listTitle: '',
    listUrl: '/sites/k',
    title: 'Kai',
    hasUniqueRoleAssignments: true,
    isProtected: false
  }
  const docs = lib('Dokumenter', false)
  const inheriting = folder('Dokumenter', '01 Tegninger', false)
  const unique = folder('Dokumenter', '02 Kontrakt', true)
  const snapshot: IAccessSnapshot = {
    targets: [web, docs, inheriting, unique, lib('Interne', true, true)],
    assignments: {
      '/sites/k': [ra(OWNERS, RoleKind.Administrator), ra(EPL, RoleKind.Reader)],
      'Dokumenter/02 Kontrakt': [ra(OWNERS, RoleKind.Administrator)],
      Interne: [ra(OWNERS, RoleKind.Administrator)]
    },
    webAssignments: [ra(OWNERS, RoleKind.Administrator), ra(EPL, RoleKind.Reader)]
  }

  it('gives access on the site without breaking inheritance or touching the fixed role', () => {
    const plan = planAccessChanges({
      snapshot,
      partyId: PARTY,
      externalProjectManagerId: EPL,
      desired: { '/sites/k': 'Reader' }
    })
    expect(stepTypes(plan.steps)).toEqual(['add:/sites/k'])
    expect(plan.changes[0]).toEqual(
      expect.objectContaining({ kind: 'add', breaksInheritance: false })
    )
  })

  it('drops choices that inherit from a chosen target', () => {
    const desired = {
      '/sites/k': 'Reader' as const,
      Dokumenter: 'Contributor' as const,
      'Dokumenter/01 Tegninger': 'Reader' as const,
      'Dokumenter/02 Kontrakt': 'Contributor' as const
    }
    expect(inheritedFrom(snapshot, inheriting, desired)?.target.key).toBe('Dokumenter')
    expect(inheritedFrom(snapshot, docs, desired)?.target.key).toBe('/sites/k')
    expect(inheritedFrom(snapshot, unique, desired)).toBeUndefined()
    expect(Object.keys(pruneInheritedDesired(snapshot, desired)).sort()).toEqual([
      '/sites/k',
      'Dokumenter/02 Kontrakt'
    ])
    const plan = planAccessChanges({
      snapshot,
      partyId: PARTY,
      externalProjectManagerId: EPL,
      desired
    })
    // Only the site and the folder with unique permissions. The folder gets no fixed-role step,
    // because the fixed role is missing there: that is expected and done.
    expect(plan.steps.map((s) => `${s.type}:${s.target.key}`)).toEqual([
      'add:/sites/k',
      'add:Dokumenter/02 Kontrakt',
      'ensureExternalProjectManager:Dokumenter/02 Kontrakt'
    ])
  })

  it('changes and removes access on the site', () => {
    const withParty: IAccessSnapshot = {
      ...snapshot,
      assignments: {
        ...snapshot.assignments,
        '/sites/k': [...snapshot.assignments['/sites/k'], ra(PARTY, RoleKind.Reader)]
      }
    }
    expect(currentDesiredAccess(withParty, PARTY)).toEqual({ '/sites/k': 'Reader' })
    const change = planAccessChanges({
      snapshot: withParty,
      partyId: PARTY,
      desired: { '/sites/k': 'Contributor' }
    })
    expect(stepTypes(change.steps)).toEqual(['change:/sites/k'])
    const remove = planAccessChanges({ snapshot: withParty, partyId: PARTY, desired: {} })
    expect(stepTypes(remove.steps)).toEqual(['remove:/sites/k'])
  })
})
