/* eslint-disable require-await */
import { type IAccessSnapshot, type IAccessTarget, RoleKind } from '../../models/IExternalParties'
import { planAccessChanges } from './accessPlanner'
import { toLogItem } from './activityLogItem'
import { type IActivityLogEntry, runOperations } from './operationRunner'
import { DEFAULT_PART_TYPES } from './partyConfig'
import { defineNewParty } from './partyNaming'
import {
  buildAccessOperations,
  buildNewPartyOperations,
  type INewPartyContext,
  type IPartiesWriter,
  type ISecurableRef
} from './partyOperations'

const EPL = 10
const PARTY = 20

/** In-memory SharePoint with the calls recorded. */
class FakeWriter implements IPartiesWriter {
  public calls: string[] = []
  public groups = new Map<string, { id: number; description: string }>()
  public libraries = new Map<string, { id: string; title: string; description: string }>()
  public folders = new Map<string, string[]>()
  public unique = new Set<string>()
  public roles = new Map<string, RoleKind[]>()
  public failOn?: string
  public links = new Set<string>()

  private _key = (ref: ISecurableRef): string =>
    `${ref.listId}${ref.itemId ? `#${ref.itemId}` : ''}`
  private _call(name: string): void {
    this.calls.push(name)
    if (this.failOn === name) throw new Error(`Feil i ${name}`)
  }

  public async findGroup(title: string) {
    return this.groups.get(title)
  }
  public async createGroup(title: string, description: string) {
    this._call(`createGroup ${title}`)
    this.groups.set(title, { id: PARTY, description })
    return PARTY
  }
  public async findLibrary(url: string) {
    return this.libraries.get(url)
  }
  public async libraryTitleInUse(title: string, exceptUrl: string) {
    return Array.from(this.libraries.entries()).some(
      ([url, l]) => l.title === title && url !== exceptUrl
    )
  }
  public async createLibrary(urlName: string, title: string, description: string) {
    this._call(`createLibrary ${urlName}`)
    this.libraries.set(`/sites/k/${urlName}`, { id: urlName, title, description })
    return urlName
  }
  public async ensureFolders(listId: string, names: string[]) {
    const have = this.folders.get(listId) || []
    const missing = names.filter((n) => !have.includes(n))
    if (missing.length) this._call(`ensureFolders ${missing.length}`)
    this.folders.set(listId, [...have, ...missing])
    return missing.length
  }
  public async hasUniqueRoleAssignments(ref: ISecurableRef) {
    return this.unique.has(this._key(ref))
  }
  public async breakInheritance(ref: ISecurableRef) {
    this._call(`break ${this._key(ref)}`)
    this.unique.add(this._key(ref))
  }
  public async getRoleKinds(ref: ISecurableRef, principalId: number) {
    return this.roles.get(`${this._key(ref)}:${principalId}`) || []
  }
  public async addRole(ref: ISecurableRef, principalId: number, kind: RoleKind) {
    this._call(`add ${this._key(ref)}:${principalId}:${RoleKind[kind]}`)
    const key = `${this._key(ref)}:${principalId}`
    this.roles.set(key, [...(this.roles.get(key) || []), kind])
  }
  public async removePrincipal(ref: ISecurableRef, principalId: number) {
    this._call(`remove ${this._key(ref)}:${principalId}`)
    this.roles.delete(`${this._key(ref)}:${principalId}`)
  }
  public async ensureNavigationLink(heading: string, title: string) {
    if (this.links.has(`${heading}/${title}`)) return false
    this._call(`nav ${heading}/${title}`)
    this.links.add(`${heading}/${title}`)
    return true
  }
}

const definition = defineNewParty(
  { name: 'Leverandør A', type: DEFAULT_PART_TYPES[1], ownLibrary: true, code: 'AB' },
  'Kai',
  '/sites/k',
  '{sitename} – '
)

describe('buildNewPartyOperations', () => {
  it('creates group, library, access and link, and does nothing on a second run', async () => {
    const writer = new FakeWriter()
    const context: INewPartyContext = {}
    const options = { externalProjectManagerId: EPL, navigationHeading: 'Dokumentsamhandling' }
    const first = await runOperations(buildNewPartyOperations(writer, definition, options, context))
    expect(first.ok).toBe(true)
    expect(writer.calls).toEqual([
      'createGroup Kai – Leverandør A',
      'createLibrary LevAB',
      'ensureFolders 3',
      'break LevAB',
      'add LevAB:20:Contributor',
      'add LevAB:10:Reader',
      'nav Dokumentsamhandling/Leverandør – Leverandør A'
    ])
    expect(context).toEqual({ groupId: PARTY, listId: 'LevAB' })

    writer.calls = []
    const second = await runOperations(buildNewPartyOperations(writer, definition, options))
    expect(second.ok).toBe(true)
    expect(writer.calls).toEqual([])
    expect(second.states.map((s) => s.status)).toEqual([
      'done',
      'skipped',
      'skipped',
      'skipped',
      'skipped',
      'skipped',
      'skipped'
    ])
  })

  it('stops before creating anything when the names are taken by something else', async () => {
    const writer = new FakeWriter()
    writer.groups.set('Kai – Leverandør A', { id: 5, description: 'Vanlig gruppe' })
    const result = await runOperations(buildNewPartyOperations(writer, definition, {}))
    expect(result.ok).toBe(false)
    expect(result.states[0]).toEqual(expect.objectContaining({ status: 'failed' }))
    expect(result.states[1].status).toBe('pending')
    expect(writer.calls).toEqual([])

    const other = new FakeWriter()
    other.libraries.set('/sites/k/Annet', {
      id: 'x',
      title: definition.library.title,
      description: ''
    })
    const titleTaken = await runOperations(buildNewPartyOperations(other, definition, {}))
    expect(titleTaken.ok).toBe(false)
  })
})

const target = (key: string, unique: boolean, itemId?: number): IAccessTarget => ({
  key,
  kind: itemId ? 'folder' : 'library',
  listId: itemId ? 'Docs' : key,
  listTitle: key,
  listUrl: key,
  itemId,
  title: key,
  hasUniqueRoleAssignments: unique,
  isProtected: false
})

describe('buildAccessOperations', () => {
  const snapshot: IAccessSnapshot = {
    targets: [target('Docs', false), target('Docs/01', false, 7), target('LevA', true)],
    assignments: {
      LevA: [
        {
          principalId: PARTY,
          principalTitle: 'P',
          principalType: 8,
          roles: [{ kind: RoleKind.Reader, name: 'Lese' }]
        }
      ]
    },
    webAssignments: []
  }

  it('runs the plan steps and writes log entries for work done', async () => {
    const writer = new FakeWriter()
    writer.unique.add('LevA')
    writer.roles.set(`LevA:${PARTY}`, [RoleKind.Reader])
    const plan = planAccessChanges({
      snapshot,
      partyId: PARTY,
      externalProjectManagerId: EPL,
      desired: { 'Docs/01': 'Contributor', LevA: 'Contributor' }
    })
    const entries: IActivityLogEntry[] = []
    const progress: string[] = []
    const result = await runOperations(
      buildAccessOperations(writer, plan, { id: PARTY, title: 'Kai – Lev A' }, EPL),
      {
        correlationId: 'c1',
        logger: {
          write: async (e) => {
            entries.push(e)
          }
        },
        onProgress: (s) => progress.push(s.map((x) => x.status[0]).join(''))
      }
    )
    expect(result.ok).toBe(true)
    expect(writer.calls).toEqual([
      'break Docs#7',
      'add Docs#7:20:Contributor',
      'add Docs#7:10:Reader',
      'remove LevA:20',
      'add LevA:20:Contributor'
    ])
    expect(entries.map((e) => [e.action, e.targetType, e.status])).toEqual([
      ['breakInheritance', 'Folder', 'Success'],
      ['addRole', 'Folder', 'Success'],
      ['ensureExternalProjectManager', 'Folder', 'Success'],
      ['changeRole', 'Library', 'Success']
    ])
    expect(toLogItem(entries[3])).toEqual(
      expect.objectContaining({
        LogSource: 'Samarbeidsparter',
        LogPrincipal: 'Kai – Lev A',
        LogRole: 'Contributor',
        LogCorrelationId: 'c1'
      })
    )
    expect(progress[0]).toBe('rppp')
    expect(progress[progress.length - 1]).toBe('dddd')
  })

  it('stops at the first failure, logs it, and continues on a new run', async () => {
    const writer = new FakeWriter()
    writer.failOn = 'add Docs#7:20:Reader'
    const plan = planAccessChanges({
      snapshot,
      partyId: PARTY,
      desired: { 'Docs/01': 'Reader', LevA: 'Reader' }
    })
    const entries: IActivityLogEntry[] = []
    const failing = {
      write: async (e: IActivityLogEntry) => {
        entries.push(e)
        throw new Error('loggen feilet')
      }
    }
    const first = await runOperations(
      buildAccessOperations(writer, plan, { id: PARTY, title: 'P' }),
      {
        logger: failing
      }
    )
    expect(first.ok).toBe(false)
    expect(first.states.map((s) => s.status)).toEqual(['done', 'failed'])
    expect(first.states[1].error).toBe('Feil i add Docs#7:20:Reader')
    expect(entries.map((e) => e.status)).toEqual(['Success', 'Failed'])

    writer.failOn = undefined
    writer.calls = []
    const second = await runOperations(
      buildAccessOperations(writer, plan, { id: PARTY, title: 'P' })
    )
    expect(second.ok).toBe(true)
    expect(second.states.map((s) => s.status)).toEqual(['skipped', 'done'])
  })
})
