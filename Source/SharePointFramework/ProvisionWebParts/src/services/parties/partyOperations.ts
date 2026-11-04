import { type IAccessTarget, type PartyRole, RoleKind } from '../../models/IExternalParties'
import type { IAccessPlan } from './accessPlanner'
import { partyRoleToKind } from './accessModel'
import type { IOperation } from './operationRunner'
import type { INewPartyDefinition } from './partyNaming'
import { PARTY_MARKER_PREFIX } from './partyMarker'

/** A library, or a folder in a library, that role assignments are set on. */
export interface ISecurableRef {
  listId: string
  itemId?: number
  /** The site itself. listId and itemId are not used. */
  web?: boolean
}

/**
 * The SharePoint writes the web part needs. Implemented by
 * PartiesProvisioningService. Kept as an interface so the operations can be
 * tested without SharePoint.
 */
export interface IPartiesWriter {
  findGroup(title: string): Promise<{ id: number; description: string } | undefined>
  /** Creates the group, makes the owner group its owner and removes the creator as member. */
  createGroup(title: string, description: string): Promise<number>
  findLibrary(
    serverRelativeUrl: string
  ): Promise<{ id: string; title: string; description: string } | undefined>
  /** True when another library than the one at exceptUrl has the title. */
  libraryTitleInUse(title: string, exceptUrl: string): Promise<boolean>
  createLibrary(urlName: string, title: string, description: string): Promise<string>
  /** Creates the folders that are missing in the library root. Returns the number created. */
  ensureFolders(listId: string, names: string[]): Promise<number>
  hasUniqueRoleAssignments(ref: ISecurableRef): Promise<boolean>
  /** Breaks inheritance with copy and removes the direct access SharePoint gives the creator. */
  breakInheritance(ref: ISecurableRef): Promise<void>
  /** Roles the principal has directly on the object (hidden roles left out). */
  getRoleKinds(ref: ISecurableRef, principalId: number): Promise<RoleKind[]>
  addRole(ref: ISecurableRef, principalId: number, kind: RoleKind): Promise<void>
  /** Removes all the principal's roles on the object. */
  removePrincipal(ref: ISecurableRef, principalId: number): Promise<void>
  /** Adds the link under the heading. Creates the heading when it is missing. */
  ensureNavigationLink(heading: string, title: string, url: string): Promise<boolean>
}

/** A group by id and title. The title is written to the activity log. */
export interface IPrincipalRef {
  id: number
  title: string
  /** Short name shown in the UI, e.g. «Ekstern prosjektleder». Defaults to the title. */
  name?: string
}

/** Error with a code the UI can translate. */
export class PartyOperationError extends Error {
  constructor(
    public readonly code: 'GroupExists' | 'LibraryUrlInUse' | 'LibraryTitleInUse',
    message: string
  ) {
    super(message)
    this.name = 'PartyOperationError'
  }
}

const hasMarker = (description: string | undefined): boolean =>
  (description || '').startsWith(PARTY_MARKER_PREFIX)

const toRef = (target: IAccessTarget): ISecurableRef =>
  target.kind === 'web'
    ? { listId: '', web: true }
    : { listId: target.listId, itemId: target.kind === 'folder' ? target.itemId : undefined }

const targetType = (target: IAccessTarget): 'Site' | 'Library' | 'Folder' =>
  target.kind === 'web' ? 'Site' : target.kind === 'folder' ? 'Folder' : 'Library'

export interface INewPartyContext {
  groupId?: number
  listId?: string
}

/**
 * Operations for a new party, in the order of New-Samarbeidspart.ps1: check
 * names, group, own library with folders, break inheritance with copy, the
 * party's role, the external project manager, and a quick launch link. The
 * group id and library id are written to the context for the next step.
 */
export const buildNewPartyOperations = (
  writer: IPartiesWriter,
  definition: INewPartyDefinition,
  options: { externalProjectManager?: IPrincipalRef; navigationHeading?: string },
  context: INewPartyContext = {}
): IOperation[] => {
  const { groupTitle, library } = definition
  const ops: IOperation[] = [
    {
      id: 'check',
      label: { action: 'check', target: definition.name },
      run: async () => {
        const group = await writer.findGroup(groupTitle)
        if (group && !hasMarker(group.description)) {
          throw new PartyOperationError('GroupExists', groupTitle)
        }
        if (library) {
          const existing = await writer.findLibrary(library.serverRelativeUrl)
          if (existing && !hasMarker(existing.description)) {
            throw new PartyOperationError('LibraryUrlInUse', library.serverRelativeUrl)
          }
          if (await writer.libraryTitleInUse(library.title, library.serverRelativeUrl)) {
            throw new PartyOperationError('LibraryTitleInUse', library.title)
          }
        }
        return 'done'
      }
    },
    {
      id: 'group',
      label: { action: 'createGroup', target: groupTitle },
      log: { targetType: 'Group', principal: groupTitle },
      run: async () => {
        const existing = await writer.findGroup(groupTitle)
        if (existing) {
          context.groupId = existing.id
          return 'skipped'
        }
        context.groupId = await writer.createGroup(groupTitle, definition.groupDescription)
        return 'done'
      }
    }
  ]
  if (!library) return ops

  const ref = (): ISecurableRef => ({ listId: context.listId })
  ops.push(
    {
      id: 'library',
      label: { action: 'createLibrary', target: library.title },
      log: { targetType: 'Library', targetUrl: library.serverRelativeUrl },
      run: async () => {
        const existing = await writer.findLibrary(library.serverRelativeUrl)
        context.listId = existing
          ? existing.id
          : await writer.createLibrary(library.urlName, library.title, library.description)
        const created = await writer.ensureFolders(context.listId, library.folders)
        return existing && created === 0 ? 'skipped' : 'done'
      }
    },
    {
      id: 'library-break',
      label: { action: 'breakInheritance', target: library.title },
      log: { targetType: 'Library', targetUrl: library.serverRelativeUrl },
      run: async () => {
        if (await writer.hasUniqueRoleAssignments(ref())) return 'skipped'
        await writer.breakInheritance(ref())
        return 'done'
      }
    },
    {
      id: 'library-role',
      label: { action: 'addRole', target: library.title, role: library.role },
      log: {
        targetType: 'Library',
        targetUrl: library.serverRelativeUrl,
        principal: groupTitle,
        role: library.role
      },
      run: async () => {
        const kind = partyRoleToKind(library.role)
        const roles = await writer.getRoleKinds(ref(), context.groupId)
        if (roles.includes(kind)) return 'skipped'
        await writer.addRole(ref(), context.groupId, kind)
        return 'done'
      }
    }
  )
  if (options.externalProjectManager) {
    const epl = options.externalProjectManager
    ops.push({
      id: 'library-epl',
      label: {
        action: 'ensureExternalProjectManager',
        target: library.title,
        principal: epl.name || epl.title
      },
      log: {
        targetType: 'Library',
        targetUrl: library.serverRelativeUrl,
        principal: epl.title,
        role: 'Reader'
      },
      run: async () => {
        if ((await writer.getRoleKinds(ref(), epl.id)).length > 0) return 'skipped'
        await writer.addRole(ref(), epl.id, RoleKind.Reader)
        return 'done'
      }
    })
  }
  if (options.navigationHeading) {
    ops.push({
      id: 'navigation',
      label: { action: 'addNavigationLink', target: library.title },
      log: { targetType: 'Navigation', targetUrl: library.serverRelativeUrl },
      run: async () =>
        (await writer.ensureNavigationLink(
          options.navigationHeading,
          library.title,
          library.serverRelativeUrl
        ))
          ? 'done'
          : 'skipped'
    })
  }
  return ops
}

/**
 * Operations for an access plan from planAccessChanges. Each step checks the
 * current state first, so a plan can be run again after a failure.
 */
export const buildAccessOperations = (
  writer: IPartiesWriter,
  plan: IAccessPlan,
  party: IPrincipalRef,
  externalProjectManager?: IPrincipalRef
): IOperation[] =>
  plan.steps.map((step, i): IOperation => {
    const target = step.target
    const ref = toRef(target)
    const log = { targetType: targetType(target), targetUrl: target.key, principal: party.title }
    const id = `${i}-${step.type}`
    switch (step.type) {
      case 'breakInheritance':
        return {
          id,
          label: { action: 'breakInheritance', target: target.title },
          log: { targetType: log.targetType, targetUrl: log.targetUrl },
          run: async () => {
            if (await writer.hasUniqueRoleAssignments(ref)) return 'skipped'
            await writer.breakInheritance(ref)
            return 'done'
          }
        }
      case 'add':
        return {
          id,
          label: { action: 'addRole', target: target.title, role: step.role },
          log: { ...log, role: step.role },
          run: async () => {
            const kind = partyRoleToKind(step.role)
            if ((await writer.getRoleKinds(ref, party.id)).includes(kind)) return 'skipped'
            await writer.addRole(ref, party.id, kind)
            return 'done'
          }
        }
      case 'change':
        return {
          id,
          label: { action: 'changeRole', target: target.title, role: step.role },
          log: { ...log, role: step.role },
          run: async () => {
            const kind = partyRoleToKind(step.role)
            const roles = await writer.getRoleKinds(ref, party.id)
            if (roles.length === 1 && roles[0] === kind) return 'skipped'
            if (roles.length > 0) await writer.removePrincipal(ref, party.id)
            await writer.addRole(ref, party.id, kind)
            return 'done'
          }
        }
      case 'remove':
        return {
          id,
          label: { action: 'removeRole', target: target.title },
          log,
          run: async () => {
            if ((await writer.getRoleKinds(ref, party.id)).length === 0) return 'skipped'
            await writer.removePrincipal(ref, party.id)
            return 'done'
          }
        }
      case 'ensureExternalProjectManager':
        return {
          id,
          label: {
            action: 'ensureExternalProjectManager',
            target: target.title,
            principal: externalProjectManager?.name || externalProjectManager?.title
          },
          log: {
            targetType: log.targetType,
            targetUrl: log.targetUrl,
            principal: externalProjectManager?.title,
            role: 'Reader' as PartyRole
          },
          run: async () => {
            if (!externalProjectManager) return 'skipped'
            const eplId = externalProjectManager.id
            if ((await writer.getRoleKinds(ref, eplId)).length > 0) return 'skipped'
            await writer.addRole(ref, eplId, RoleKind.Reader)
            return 'done'
          }
        }
    }
  })
