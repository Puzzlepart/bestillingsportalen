import type { SPFI } from '@pnp/sp'
import '@pnp/sp/webs'
import '@pnp/sp/lists'
import '@pnp/sp/items'
import '@pnp/sp/fields'
import '@pnp/sp/security'

import { RoleKind } from '../../models/IExternalParties'
import type { IActivityLogger, IActivityLogEntry } from './operationRunner'
import { ACTIVITY_LOG_FIELDS, fieldXml, toLogItem } from './activityLogItem'
import type { IPartiesSiteInfo } from './PartiesService'
import { toServerRelativeUrl } from './partyConfig'

/**
 * Writes who did what to a hidden list on the project site. Created the first
 * time it is needed: hidden, not crawled, and readable for the owner group
 * only. Created by and created time come from the list item itself. The web
 * part never mentions the log, and a failing log never stops the work.
 */
export class ActivityLogService implements IActivityLogger {
  private _listId: Promise<string | undefined>

  constructor(
    private readonly sp: SPFI,
    private readonly site: IPartiesSiteInfo,
    private readonly listUrl: string,
    private readonly listTitle: string
  ) {}

  public async write(entry: IActivityLogEntry): Promise<void> {
    try {
      const listId = await this._ensureList()
      if (!listId) return
      await this.sp.web.lists.getById(listId).items.add(toLogItem(entry))
    } catch {
      // Silent by design.
    }
  }

  private _ensureList(): Promise<string | undefined> {
    if (!this._listId) {
      this._listId = this._getOrCreateList().catch((): undefined => {
        // Try again next time instead of keeping the failure.
        this._listId = undefined
        return undefined
      })
    }
    return this._listId
  }

  private async _getOrCreateList(): Promise<string> {
    const serverRelativeUrl = toServerRelativeUrl(this.site.serverRelativeUrl, this.listUrl)
    try {
      const existing = (await this.sp.web.getList(serverRelativeUrl).select('Id')()) as {
        Id: string
      }
      return existing.Id
    } catch {
      // Not there yet.
    }

    // The URL comes from the title given at creation: "Lists/ActivityLog" → "ActivityLog".
    const urlName = this.listUrl.replace(/\/$/, '').split('/').pop()
    const created = await this.sp.web.lists.add(urlName, '', 100, false, {
      Hidden: true,
      NoCrawl: true,
      EnableVersioning: false
    })
    const list = this.sp.web.lists.getById(created.Id)
    for (const field of ACTIVITY_LOG_FIELDS) {
      await list.fields.createFieldAsXml(fieldXml(field))
    }
    await this.sp.web.lists.getById(created.Id).update({ Title: this.listTitle })

    // Owners only: break inheritance without copy, add the owner group, remove the creator.
    if (this.site.ownerGroupId) {
      await this.sp.web.lists.getById(created.Id).breakRoleInheritance(false, true)
      const admin = (await this.sp.web.roleDefinitions
        .getByType(RoleKind.Administrator as number as 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7)
        .select('Id')()) as { Id: number }
      await this.sp.web.lists
        .getById(created.Id)
        .roleAssignments.add(this.site.ownerGroupId, admin.Id)
      await this.sp.web.lists
        .getById(created.Id)
        .roleAssignments.getById(this.site.currentUserId)
        .delete()
        .catch((): void => undefined)
    }
    return created.Id
  }
}
