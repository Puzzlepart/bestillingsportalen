import type { SPFI } from '@pnp/sp'
import '@pnp/sp/batching'
import '@pnp/sp/webs'
import '@pnp/sp/lists'
import '@pnp/sp/items'
import '@pnp/sp/folders'
import '@pnp/sp/security'

import type { IAccessSnapshot, IAccessTarget } from '../../models/IExternalParties'
import { toRoleAssignments } from './accessModel'
import { isProtectedLibrary } from './partyConfig'

const ROLE_ASSIGNMENT_SELECT = [
  'PrincipalId',
  'Member/Title',
  'Member/PrincipalType',
  'RoleDefinitionBindings/Name',
  'RoleDefinitionBindings/RoleTypeKind',
  'RoleDefinitionBindings/Hidden'
]

/** Requests per batch. SharePoint accepts up to 100. */
const BATCH_SIZE = 50

interface IRawList {
  Id: string
  Title: string
  HasUniqueRoleAssignments: boolean
  RootFolder: { ServerRelativeUrl: string }
}

interface IRawFolder {
  Name: string
  ServerRelativeUrl: string
  ListItemAllFields?: { Id?: number; HasUniqueRoleAssignments?: boolean }
}

/**
 * Reads the access on the site as it is configured in SharePoint now:
 * libraries matching the filter, their first-level folders, and the role
 * assignments on the web and on every library or folder with unique role
 * assignments. Nothing deeper is read, so the result is not a complete
 * picture of all access on the site.
 */
export class AccessReaderService {
  constructor(private readonly sp: SPFI) {}

  public async getSnapshot(
    librariesFilter: string,
    protectedLibraries: string[]
  ): Promise<IAccessSnapshot> {
    const [lists, web] = await Promise.all([
      this.sp.web.lists
        .filter(librariesFilter)
        .select('Id', 'Title', 'HasUniqueRoleAssignments', 'RootFolder/ServerRelativeUrl')
        .expand('RootFolder')() as Promise<IRawList[]>,
      this.sp.web.select('Title', 'ServerRelativeUrl', 'HasUniqueRoleAssignments')() as Promise<{
        Title: string
        ServerRelativeUrl: string
        HasUniqueRoleAssignments: boolean
      }>
    ])

    const targets: IAccessTarget[] = lists
      .map((l) => ({
        key: l.RootFolder.ServerRelativeUrl,
        kind: 'library' as const,
        listId: l.Id,
        listTitle: l.Title,
        listUrl: l.RootFolder.ServerRelativeUrl,
        title: l.Title,
        hasUniqueRoleAssignments: l.HasUniqueRoleAssignments,
        isProtected: isProtectedLibrary(l.Title, l.RootFolder.ServerRelativeUrl, protectedLibraries)
      }))
      .sort((a, b) => a.title.localeCompare(b.title, 'nb'))

    // First-level folders. Protected libraries are not expanded: they can
    // never be shared, so their folders are not needed.
    const expandable = targets.filter((t) => !t.isProtected)
    const folderResults = await this._batched(
      expandable,
      (sp, lib) =>
        sp.web.lists
          .getById(lib.listId)
          .rootFolder.folders.select(
            'Name',
            'ServerRelativeUrl',
            'ListItemAllFields/Id',
            'ListItemAllFields/HasUniqueRoleAssignments'
          )
          .expand('ListItemAllFields')() as Promise<IRawFolder[]>
    )

    const folders: IAccessTarget[] = []
    expandable.forEach((lib, i) => {
      const raw = folderResults[i] || []
      raw
        .filter((f) => f.Name !== 'Forms' && f.ListItemAllFields?.Id)
        .sort((a, b) => a.Name.localeCompare(b.Name, 'nb'))
        .forEach((f) =>
          folders.push({
            key: f.ServerRelativeUrl,
            kind: 'folder',
            listId: lib.listId,
            listTitle: lib.listTitle,
            listUrl: lib.listUrl,
            itemId: f.ListItemAllFields.Id,
            title: `${lib.title} / ${f.Name}`,
            name: f.Name,
            hasUniqueRoleAssignments: !!f.ListItemAllFields.HasUniqueRoleAssignments,
            isProtected: false,
            parentKey: lib.key
          })
        )
    })

    const allTargets = targets.flatMap((lib) => [
      lib,
      ...folders.filter((f) => f.parentKey === lib.key)
    ])

    const unique = allTargets.filter((t) => t.hasUniqueRoleAssignments)
    const [webRaw, uniqueRaw] = await Promise.all([
      this.sp.web.roleAssignments
        .expand('Member', 'RoleDefinitionBindings')
        .select(...ROLE_ASSIGNMENT_SELECT)(),
      this._batched(unique, (sp, t) => {
        const list = sp.web.lists.getById(t.listId)
        const securable = t.kind === 'folder' ? list.items.getById(t.itemId) : list
        return securable.roleAssignments
          .expand('Member', 'RoleDefinitionBindings')
          .select(...ROLE_ASSIGNMENT_SELECT)()
      })
    ])

    const assignments: IAccessSnapshot['assignments'] = {}
    unique.forEach((t, i) => (assignments[t.key] = toRoleAssignments(uniqueRaw[i] || [])))
    const webAssignments = toRoleAssignments(webRaw as any[])

    // The site itself, first in the list. A subsite that inherits from its
    // parent cannot be shared: that would mean breaking inheritance on the site.
    const webKey = web.ServerRelativeUrl.replace(/\/$/, '') || '/'
    const webTarget: IAccessTarget = {
      key: webKey,
      kind: 'web',
      listId: '',
      listTitle: '',
      listUrl: webKey,
      title: web.Title,
      hasUniqueRoleAssignments: web.HasUniqueRoleAssignments,
      isProtected: !web.HasUniqueRoleAssignments
    }
    if (web.HasUniqueRoleAssignments) assignments[webKey] = webAssignments

    return {
      targets: [webTarget, ...allTargets],
      assignments,
      webAssignments
    }
  }

  /**
   * Runs one request per item in SharePoint batches. A failed request gives
   * undefined for that item instead of failing the whole read.
   */
  private async _batched<T, R>(
    items: T[],
    request: (sp: SPFI, item: T) => Promise<R>
  ): Promise<(R | undefined)[]> {
    const results: (R | undefined)[] = []
    for (let i = 0; i < items.length; i += BATCH_SIZE) {
      const chunk = items.slice(i, i + BATCH_SIZE)
      const [batchedSp, execute] = this.sp.batched()
      const promises = chunk.map((item) =>
        request(batchedSp, item).catch((): undefined => undefined)
      )
      await execute()
      results.push(...(await Promise.all(promises)))
    }
    return results
  }
}
