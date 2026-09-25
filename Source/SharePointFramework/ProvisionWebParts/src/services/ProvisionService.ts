/* eslint-disable no-console */

import { WebPartContext } from '@microsoft/sp-webpart-base'
import { Caching } from '@pnp/queryable'
import { spfi, SPFI, SPFx } from '@pnp/sp'
import { IWeb } from '@pnp/sp/webs'
import { PermissionKind } from '@pnp/sp/security'
import '@pnp/sp/webs'
import '@pnp/sp/sites'
import '@pnp/sp/lists'
import '@pnp/sp/items'
import '@pnp/sp/content-types/list'
import '@pnp/sp/fields'
import '@pnp/sp/files'
import '@pnp/sp/folders'
import '@pnp/sp/site-users/web'
import '@pnp/sp/site-groups/web'
import '@pnp/sp/security'
import '@pnp/sp/profiles'
import '@pnp/sp/groupsitemanager'
import * as strings from 'ProvisionWebPartsStrings'
import { IProvisionRequestItem } from '../models/IProvisionRequestItem'
import { getTenantProvisionInstances, IProvisionInstance } from './provisionInstances'
import { format } from '../utils/format'
import { normalizeHubSiteId } from '../utils/normalizeHubSiteId'

/**
 * Title of the project data list on hub sites ("Prosjektdata"). Previously
 * resolved from PP365's shared `.resx` resources (`Lists_ProjectData_Title`).
 */
export const PROJECT_DATA_LIST_TITLE = 'Prosjektdata'

/**
 * Minimal persona shape used by the people picker fields. Mirrors the
 * subset of Fluent UI v8's `IPersonaProps` the component tree relies on.
 */
export interface IProvisionPersona {
  id?: string
  text?: string
  secondaryText?: string
  tertiaryText?: string
  optionalText?: string
  imageUrl?: string
}

const DefaultCaching = Caching({ store: 'session' })

/**
 * Result of a provisioning-site access check: `notFound` means the site does
 * not exist on the given URL (HTTP 404), as opposed to a real access denial.
 */
export type ProvisionSiteAccess = 'granted' | 'denied' | 'notFound'

/**
 * Service handling all data operations for the `ProjectProvision` web part.
 * Ported from PP365's `DataAdapter` provisioning slice, rewritten for
 * PnPjs v4: instead of the v3 `Web([sp.web, url])` tuple pattern, a
 * separate `SPFI` instance is created (and cached) per target site.
 */
export class ProvisionService {
  private _webs = new Map<string, SPFI>()
  private _currentHubSite: Promise<{ hubSiteId: string; title: string; url: string } | undefined>

  constructor(private readonly _context: WebPartContext) {}

  /**
   * Returns a cached `SPFI` instance for the given site URL. Relative URLs
   * are resolved against the current web. With no URL, the current web is used.
   */
  private _spfi(url?: string): SPFI {
    const webAbsoluteUrl = this._context.pageContext.web.absoluteUrl
    const absoluteUrl = url ? new URL(url, webAbsoluteUrl).href : webAbsoluteUrl
    if (!this._webs.has(absoluteUrl)) {
      this._webs.set(absoluteUrl, spfi(absoluteUrl).using(SPFx(this._context)))
    }
    return this._webs.get(absoluteUrl)
  }

  /**
   * Returns an `IWeb` for the given site URL. Used where callers need
   * direct list/field access on another site (e.g. the hub's project
   * data list).
   */
  public web(url?: string): IWeb {
    return this._spfi(url).web
  }

  /**
   * Checks if the current user can view membership of the site group with
   * the given title on the current site. Used to gate access to the web part.
   */
  public async isUserInGroup(groupName: string): Promise<boolean> {
    try {
      const [siteGroup] = await this._spfi()
        .web.siteGroups.select('CanCurrentUserViewMembership', 'Title')
        .filter(`Title eq '${groupName}'`)<
        { CanCurrentUserViewMembership: boolean; Title: string }[]
      >()
      return siteGroup && siteGroup.CanCurrentUserViewMembership
    } catch {
      return false
    }
  }

  /**
   * Reads the tenant-wide Bestillingsportalen instance registry (storage
   * entity `bp_ProvisionUrls`) via the current web.
   */
  public getTenantProvisionInstances(): Promise<IProvisionInstance[]> {
    return getTenantProvisionInstances(this._spfi())
  }

  /**
   * Checks the current user's access to the provisioning site, distinguishing
   * between the site not being found (e.g. misconfigured URL, HTTP 404) and
   * the user actually lacking access.
   */
  public async getProvisionSiteAccess(provisionUrl: string): Promise<ProvisionSiteAccess> {
    try {
      const granted = await this._spfi(provisionUrl).web.currentUserHasPermissions(
        PermissionKind.ViewListItems
      )
      return granted ? 'granted' : 'denied'
    } catch (error) {
      if (error?.status === 404 || error?.response?.status === 404) return 'notFound'
      return 'denied'
    }
  }

  public async clientPeoplePickerSearchUser(
    queryString: string,
    selectedItems: IProvisionPersona[],
    maximumEntitySuggestions = 50
  ): Promise<IProvisionPersona[]> {
    const profiles = await this._spfi().profiles.clientPeoplePickerSearchUser({
      QueryString: queryString,
      MaximumEntitySuggestions: maximumEntitySuggestions,
      // Off: an arbitrary email address has no Entra ID account, so the
      // provisioning flow's user lookup would 404 on it.
      AllowEmailAddresses: false,
      PrincipalSource: 15,
      PrincipalType: 1
    })
    const selectedKeys = (selectedItems ?? [])
      .map((item) => this._getProvisionUserSearchKey(item))
      .filter(Boolean)
    const uniqueItems = profiles.reduce((items: IProvisionPersona[], profile) => {
      // Guests (claims key 'i:0#.f|membership|<name>_<domain>#ext#@<tenant>')
      // can't be owners or members - the flow looks them up by email and gets
      // a 404. External users are invited through the guest field instead.
      if (this._isGuestUser(profile.Key)) {
        return items
      }
      const key = this._getProvisionUserSearchKey({
        id: profile.Key,
        secondaryText: profile.EntityData.Email,
        text: profile.DisplayText
      })
      if (!key || items.some((item) => this._getProvisionUserSearchKey(item) === key)) {
        return items
      }
      return [
        ...items,
        {
          text: profile.DisplayText,
          secondaryText: profile.EntityData.Email,
          tertiaryText: profile.EntityData.Title,
          optionalText: profile.EntityData.Department,
          imageUrl: `/_layouts/15/userphoto.aspx?AccountName=${profile.EntityData.Email}&size=L`,
          id: profile.Key
        }
      ]
    }, [])
    return uniqueItems.filter(
      (item) => !selectedKeys.includes(this._getProvisionUserSearchKey(item))
    )
  }

  public async getProvisionRequestSettings(provisionUrl: string): Promise<any[]> {
    try {
      const settingsList = this._spfi(provisionUrl).web.lists.getByTitle(
        'Provisioning Request Settings'
      )
      const spItems = await settingsList.items
        .select(
          'Id',
          'Title',
          'Description',
          'Value',
          'PrefixText',
          'PrefixUseAttribute',
          'PrefixAttribute',
          'SuffixText',
          'SuffixUseAttribute',
          'SuffixAttribute',
          'ExternalSharingSetting',
          'PowerAppOnly'
        )
        .using(DefaultCaching)()

      return spItems
        .filter((item) => !item.PowerAppOnly)
        .map((item) => {
          let value = item.Value === 'true' ? true : item.Value === 'false' ? false : item.Value
          if (item.Title === 'NamingConvention') {
            value = {
              value: item.Value,
              prefixText: item.PrefixText || '',
              prefixUseAttribute: item.PrefixUseAttribute,
              prefixAttribute: item.PrefixAttribute,
              suffixText: item.SuffixText || '',
              suffixUseAttribute: item.SuffixUseAttribute,
              suffixAttribute: item.SuffixAttribute
            }
          } else if (item.Title === 'DefaultExternalSharingSetting') {
            value = {
              value: item.Value,
              externalSharingSetting: item.ExternalSharingSetting
            }
          }

          return {
            title: item.Title,
            value,
            description: item.Description
          }
        })
    } catch (error) {
      throw new Error(
        format(
          strings.Provision.ProvisionError,
          'Provisioning Request Settings',
          error.message || error
        )
      )
    }
  }

  public async getProvisionTypes(provisionUrl: string): Promise<Record<string, any>[]> {
    try {
      const typesList = this._spfi(provisionUrl).web.lists.getByTitle('Provisioning Types')
      const spItems = await typesList.items
        .select(
          'Id',
          'Title',
          'SortOrder',
          'Description',
          'Allowed',
          'Image',
          'InternalTitle',
          'PrefixText',
          'PrefixUseAttribute',
          'PrefixAttribute',
          'SuffixText',
          'SuffixUseAttribute',
          'SuffixAttribute',
          'VisibleTo/EMail',
          'DefaultVisibility',
          'DefaultConfidentialData',
          'DefaultMetadata',
          'ExternalSharing',
          'Teamify',
          'JoinHub',
          'DefaultHub',
          'DefaultSensitivityLabel',
          'DefaultSensitivityLabelLibrary',
          'DefaultRetentionLabel',
          'TemplateId'
        )
        .expand('VisibleTo')
        .using(DefaultCaching)()
      return spItems
        .filter((item) => item.Allowed)
        .sort((a, b) => (a.SortOrder > b.SortOrder ? 1 : -1))
        .map((item) => {
          return {
            order: item.SortOrder,
            title: item.Title,
            description: item.Description,
            image: item.Image,
            type: item.InternalTitle,
            namingConvention: {
              prefixText: item.PrefixText || '',
              prefixUseAttribute: item.PrefixUseAttribute,
              prefixAttribute: item.PrefixAttribute,
              suffixText: item.SuffixText || '',
              suffixUseAttribute: item.SuffixUseAttribute,
              suffixAttribute: item.SuffixAttribute
            },
            visibleTo: item.VisibleTo,
            defaultVisibility: item.DefaultVisibility,
            defaultConfidentialData: item.DefaultConfidentialData,
            defaultMetadata: item.DefaultMetadata,
            externalSharing: item.ExternalSharing,
            templateId: item.TemplateId,
            teamify: item.Teamify,
            joinHub: item.JoinHub,
            defaultHub: item.DefaultHub,
            defaultSensitivityLabel: item.DefaultSensitivityLabel,
            defaultSensitivityLabelLibrary: item.DefaultSensitivityLabelLibrary,
            defaultRetentionLabel: item.DefaultRetentionLabel
          }
        })
    } catch (error) {
      throw new Error(
        format(strings.Provision.ProvisionError, 'Provisioning Types', error.message || error)
      )
    }
  }

  public async getSiteTemplates(provisionUrl: string): Promise<Record<string, any>[]> {
    try {
      const templatesList = this._spfi(provisionUrl).web.lists.getByTitle('Site Templates')
      const spItems = await templatesList.items
        .select('Id', 'Title', 'ApplyPnPTemplate', 'PnPTemplateURL')
        .using(DefaultCaching)()
      return spItems.map((item) => {
        return {
          id: item.Id,
          title: item.Title,
          applyPnPTemplate: item.ApplyPnPTemplate,
          pnpTemplateUrl: item.PnPTemplateURL?.Url || ''
        }
      })
    } catch (error) {
      throw new Error(
        format(strings.Provision.ProvisionError, 'Site Templates', error.message || error)
      )
    }
  }

  /**
   * Adds a provisioning request. People fields (Owners/Members/RequestedBy)
   * are stripped from the item body and applied afterwards with
   * `validateUpdateListItem`, which resolves users server-side — client-side
   * `ensureUser` requires more than read access on the ordering site and
   * failed for ordinary users.
   */
  public async addProvisionRequests(
    properties: IProvisionRequestItem,
    provisionUrl: string
  ): Promise<boolean | 'userResolveError'> {
    try {
      const provisionRequestsList =
        this._spfi(provisionUrl).web.lists.getByTitle('Provisioning Requests')
      const { itemProperties, userFieldUpdates } = this._extractProvisionUserFields(properties)
      const added = (await provisionRequestsList.items.add(itemProperties)) as { Id?: number }
      if (userFieldUpdates.length > 0 && added?.Id) {
        const item = provisionRequestsList.items.getById(added.Id)
        const updateResults = await item.validateUpdateListItem(userFieldUpdates)
        const failedUpdates = (updateResults ?? []).filter(
          (updateResult) => updateResult.HasException
        )
        if (failedUpdates.length > 0) {
          console.error(
            '(ProvisionService) (addProvisionRequests) Failed to resolve provision request users:',
            failedUpdates
          )
          try {
            await item.delete()
          } catch (deleteError) {
            console.error(
              '(ProvisionService) (addProvisionRequests) Failed to delete incomplete provision request:',
              deleteError
            )
          }
          return 'userResolveError'
        }
      }
      return true
    } catch (error) {
      console.error(
        '(ProvisionService) (addProvisionRequests) Failed to add provision request:',
        error
      )
      return error?.code === 'ProvisionUserResolveError' ? 'userResolveError' : false
    }
  }

  private _extractProvisionUserFields(properties: IProvisionRequestItem): {
    itemProperties: IProvisionRequestItem
    userFieldUpdates: { FieldName: string; FieldValue: string }[]
  } {
    const itemProperties = { ...properties }
    const userFieldUpdates: { FieldName: string; FieldValue: string }[] = []
    const userFields: { itemFieldName: keyof IProvisionRequestItem; updateFieldName: string }[] = [
      { itemFieldName: 'OwnersId', updateFieldName: 'Owners' },
      { itemFieldName: 'MembersId', updateFieldName: 'Members' },
      { itemFieldName: 'RequestedById', updateFieldName: 'RequestedBy' }
    ]

    userFields.forEach(({ itemFieldName, updateFieldName }) => {
      const value = itemProperties[itemFieldName]
      if (Array.isArray(value) && value.length === 0) {
        delete itemProperties[itemFieldName]
      } else if (this._shouldValidateProvisionUserField(value)) {
        userFieldUpdates.push(this._getProvisionUserFieldUpdate(updateFieldName, value))
        delete itemProperties[itemFieldName]
      }
    })

    return { itemProperties, userFieldUpdates }
  }

  private _getProvisionUserFieldUpdate(
    fieldName: string,
    users: any
  ): { FieldName: string; FieldValue: string } {
    const userValues = Array.isArray(users) ? users : users ? [users] : []
    const fieldValue = userValues.map((user) => ({ Key: this._getProvisionUserLoginKey(user) }))
    if (fieldValue.some((user) => !user.Key)) {
      throw this._createProvisionUserResolveError(`Missing user key for ${fieldName}`)
    }

    return {
      FieldName: fieldName,
      FieldValue: JSON.stringify(fieldValue)
    }
  }

  // Numeric values are already-resolved SharePoint user ids (legacy rows and
  // retry paths) and stay in the item body as plain OwnersId/... assignments.
  private _shouldValidateProvisionUserField(users: any): boolean {
    const userValues = Array.isArray(users) ? users : users ? [users] : []
    return userValues.length > 0 && userValues.every((user) => typeof user !== 'number')
  }

  private _isGuestUser(claimsKey: string): boolean {
    return (claimsKey || '').toLowerCase().includes('#ext#')
  }

  private _getProvisionUserSearchKey(user: any): string {
    if (!user) {
      return ''
    }
    if (typeof user === 'string') {
      return user.toLowerCase()
    }
    const key = (user.secondaryText || user.id || user.text || '').toLowerCase()
    return key.includes('|') ? key.split('|').pop() || key : key
  }

  private _getProvisionUserLoginKey(user: any): string {
    if (!user) {
      return ''
    }
    if (typeof user === 'string') {
      return user.toLowerCase()
    }
    const key = user.id || user.secondaryText || user.text || ''
    if (!key) {
      return ''
    }
    return key.includes('|') ? key.toLowerCase() : `i:0#.f|membership|${key}`.toLowerCase()
  }

  private _createProvisionUserResolveError(message: string): Error & { code: string } {
    const error = new Error(message) as Error & { code: string }
    error.code = 'ProvisionUserResolveError'
    return error
  }

  public async addProjectData(
    properties: Record<string, any>,
    hubUrl: string
  ): Promise<Record<string, any> | void> {
    try {
      const list = this._spfi(hubUrl).web.lists.getByTitle(PROJECT_DATA_LIST_TITLE)
      return await list.items.add(properties)
    } catch (error) {
      console.warn('Failed to add project data to ProjectData list:', error)
    }
  }

  public async deleteProvisionRequest(requestId: number, provisionUrl: string): Promise<boolean> {
    try {
      const provisionRequestsList =
        this._spfi(provisionUrl).web.lists.getByTitle('Provisioning Requests')
      await provisionRequestsList.items.getById(requestId).delete()
      return true
    } catch {
      return false
    }
  }

  public async fetchProvisionRequests(user: string, provisionUrl: string): Promise<any[]> {
    try {
      const provisionRequestsList =
        this._spfi(provisionUrl).web.lists.getByTitle('Provisioning Requests')
      // PnPjs v4 removed `getAll()` — page through all items with the
      // async iterator instead.
      const spItems: any[] = []
      const pagedItems = provisionRequestsList.items
        .select(
          'Id',
          'Title',
          'SpaceDisplayName',
          'SpaceType',
          'SiteURL',
          'Status',
          'StatusReason',
          'Stage',
          'Comments',
          'ApprovedDate',
          'Created',
          'Author/EMail',
          'RequestedBy/EMail'
        )
        .expand('Author', 'RequestedBy')
        .top(500)
      for await (const page of pagedItems) {
        spItems.push(...page)
      }
      return spItems
        .filter((item) => item.Author?.EMail === user || item?.RequestedBy?.EMail === user)
        .sort((a, b) => (a.Created > b.Created ? 1 : -1))
        .map((item) => {
          return {
            id: item.Id,
            title: item.Title,
            displayName: item.SpaceDisplayName,
            type: item.SpaceType,
            siteUrl: item.SiteURL?.Url,
            status: item.Status,
            statusReason: item.StatusReason,
            stage: item.Stage,
            comments: item.Comments,
            approvedDate: item.ApprovedDate,
            created: item.Created,
            author: item.Author?.EMail,
            requestedBy: item.RequestedBy?.EMail
          }
        })
    } catch (error) {
      throw new Error(
        format(strings.Provision.ProvisionError, 'Provisioning Requests', error.message || error)
      )
    }
  }

  public async getTeamTemplates(provisionUrl: string): Promise<Record<string, any>[]> {
    try {
      const templatesList = this._spfi(provisionUrl).web.lists.getByTitle('Teams Templates')
      const spItems = await templatesList.items
        .select('Id', 'Title', 'TemplateId', 'Description')
        .using(DefaultCaching)()
      return [
        {
          title: 'Standard',
          templateId: 'standard',
          description: strings.Provision.StandardTeamTemplate
        },
        ...spItems.map((item) => {
          return {
            title: item.Title,
            templateId: item.TemplateId,
            description: item.Description
          }
        })
      ].sort((a, b) => (a.title > b.title ? 1 : -1))
    } catch (error) {
      throw new Error(
        format(strings.Provision.ProvisionError, 'Teams Templates', error.message || error)
      )
    }
  }

  public async getSensitivityLabels(provisionUrl: string): Promise<Record<string, any>[]> {
    try {
      const labelsList = this._spfi(provisionUrl).web.lists.getByTitle('IP Labels')
      const spItems = await labelsList.items
        .select('Id', 'Title', 'LabelName', 'LabelId', 'LabelDescription', 'Enabled', 'IsLibrary')
        .using(DefaultCaching)()
      return spItems
        .filter((item) => item.Enabled)
        .sort((a, b) => (a.Title > b.Title ? 1 : -1))
        .map((item) => {
          return {
            title: item.Title,
            labelName: item.LabelName,
            labelId: item.LabelId,
            labelDescription: item.LabelDescription,
            isLibrary: item.IsLibrary
          }
        })
    } catch (error) {
      throw new Error(format(strings.Provision.ProvisionError, 'IP Labels', error.message || error))
    }
  }

  public async getRetentionLabels(provisionUrl: string): Promise<Record<string, any>[]> {
    try {
      const labelsList = this._spfi(provisionUrl).web.lists.getByTitle('Retention Labels')
      const spItems = await labelsList.items
        .select('Id', 'Title', 'LabelName', 'LabelDescription')
        .using(DefaultCaching)()
      return spItems
        .sort((a, b) => (a.Title > b.Title ? 1 : -1))
        .map((item) => {
          return {
            title: item.Title,
            labelName: item.LabelName,
            labelDescription: item.LabelDescription
          }
        })
    } catch (error) {
      throw new Error(
        format(strings.Provision.ProvisionError, 'Retention Labels', error.message || error)
      )
    }
  }

  public async siteExists(siteUrl: string): Promise<boolean> {
    const normalizedUrl = siteUrl.replace(/\/+$/, '')
    try {
      const exists = await this._spfi().site.exists(normalizedUrl)
      if (exists) return true
    } catch (error) {
      console.warn('(ProvisionService) (siteExists) SP.Site.Exists check failed:', error)
    }
    // SP.Site.Exists only reports live site collections. The URL can still be
    // unavailable — the site may sit in the tenant recycle bin, or the alias
    // may be taken by an existing Microsoft 365 group. GetValidSiteUrlFromAlias
    // (used by SharePoint's own site creation form) returns a modified URL in
    // those cases.
    try {
      const pathSegments = new URL(normalizedUrl).pathname.split('/').filter(Boolean)
      if (pathSegments.length < 2) return false
      const alias = pathSegments.pop()
      const managedPath = `/${pathSegments.pop()}`
      const validUrl = await this._spfi().groupSiteManager.getValidSiteUrlFromAlias(
        alias,
        managedPath,
        true
      )
      return (
        !!validUrl && validUrl.replace(/\/+$/, '').toLowerCase() !== normalizedUrl.toLowerCase()
      )
    } catch (error) {
      console.warn('(ProvisionService) (siteExists) GetValidSiteUrlFromAlias check failed:', error)
      return false
    }
  }

  /**
   * Checks if an in-flight provisioning request with the same site alias
   * already exists in the "Provisioning Requests" list. Only requests that
   * are still in flight block the alias: rejected and failed requests may be
   * resubmitted, and created sites are detected by `siteExists` (blocking on
   * them here would leave stale requests in the way if the site is later
   * deleted).
   *
   * @param siteAlias Full site alias (including naming convention prefix/suffix)
   * @param provisionUrl URL of the provisioning site
   */
  public async provisionRequestExists(siteAlias: string, provisionUrl: string): Promise<boolean> {
    try {
      const provisionRequestsList =
        this._spfi(provisionUrl).web.lists.getByTitle('Provisioning Requests')
      const escapedAlias = siteAlias.replace(/'/g, "''")
      const items = await provisionRequestsList.items
        .select('Id', 'SiteAlias', 'Status')
        .filter(`SiteAlias eq '${escapedAlias}'`)
        .top(10)()
      const blockingStatuses: string[] = [
        'Submitted',
        'Pending Approval',
        'Approved',
        'Team Requested',
        'Space Creation'
      ]
      return items.some((item) => blockingStatuses.includes(item.Status))
    } catch (error) {
      console.warn(
        '(ProvisionService) (provisionRequestExists) Failed to check provisioning requests:',
        error
      )
      return false
    }
  }

  public async loadTeamsConfig(provisionUrl: string): Promise<any> {
    try {
      const file = this._spfi(provisionUrl)
        .web.getFolderByServerRelativePath('SiteAssets')
        .files.getByUrl('TeamsAppConfig.json')
      const content = await file.getText()
      return JSON.parse(content)
    } catch (error) {
      console.log('TeamsAppConfig.json not found or error loading:', error.message)
      return undefined
    }
  }

  public async saveTeamsConfig(provisionUrl: string, config: any): Promise<void> {
    try {
      const provisionWeb = this._spfi(provisionUrl).web
      const hasPermission = await provisionWeb.currentUserHasPermissions(PermissionKind.ManageWeb)

      if (!hasPermission) {
        throw new Error(
          'You do not have permission to edit configuration. Site administrator access required.'
        )
      }

      const folder = provisionWeb.getFolderByServerRelativePath('SiteAssets')
      const jsonContent = JSON.stringify(config, null, 2)

      try {
        const file = folder.files.getByUrl('TeamsAppConfig.json')
        await file.getText()
        await file.setContent(jsonContent)
      } catch {
        await folder.files.addUsingPath('TeamsAppConfig.json', jsonContent, { Overwrite: true })
      }
    } catch (error) {
      throw new Error(`Failed to save TeamsAppConfig.json: ${error.message || error}`)
    }
  }

  public async deleteTeamsConfig(provisionUrl: string): Promise<void> {
    try {
      const file = this._spfi(provisionUrl)
        .web.getFolderByServerRelativePath('SiteAssets')
        .files.getByUrl('TeamsAppConfig.json')
      await file.recycle()
    } catch (error: any) {
      throw new Error(`Failed to delete TeamsAppConfig.json: ${error?.message || error}`)
    }
  }

  public async isProvisionSiteAdmin(provisionUrl: string): Promise<boolean> {
    try {
      return await this._spfi(provisionUrl).web.currentUserHasPermissions(PermissionKind.ManageWeb)
    } catch (error) {
      console.warn('Failed to check provision site admin status:', error)
      return false
    }
  }

  /**
   * Resolve a hub site by its ID using the SharePoint HubSites REST API.
   * Returns the hub site title, normalized ID and site URL, or null if the hub
   * site could not be resolved.
   *
   * The returned ID is normalized (lowercase, no braces) so it can be compared
   * against `legacyPageContext.hubSiteId` regardless of how it was entered in
   * the `Provisioning Types` list.
   *
   * @param hubSiteId Hub site ID (GUID)
   */
  public async resolveHubSiteById(
    hubSiteId: string
  ): Promise<{ hubSiteId: string; title: string; url: string } | undefined> {
    const normalizedId = normalizeHubSiteId(hubSiteId)
    if (!normalizedId) return undefined
    try {
      const webAbsoluteUrl = this._context.pageContext.web.absoluteUrl
      const response = await fetch(`${webAbsoluteUrl}/_api/HubSites/GetById('${normalizedId}')`, {
        method: 'GET',
        headers: { Accept: 'application/json;odata=nometadata' },
        credentials: 'include'
      })
      if (!response.ok) return undefined
      const hubSite = await response.json()
      return {
        hubSiteId: normalizeHubSiteId(hubSite.ID) || normalizedId,
        title: hubSite.Title || '',
        url: hubSite.SiteUrl || ''
      }
    } catch (error) {
      console.warn('Failed to resolve hub site by ID:', error)
      return undefined
    }
  }

  /**
   * Resolves the hub site of the CURRENT site (via
   * `legacyPageContext.hubSiteId`), or undefined when the current site is not
   * associated with a hub. The result is cached for the lifetime of the
   * service. Replaces PP365's `portalDataService.url`, which pointed at the
   * portfolio hub the web part was installed on.
   */
  public getCurrentHubSite(): Promise<
    { hubSiteId: string; title: string; url: string } | undefined
  > {
    if (!this._currentHubSite) {
      const hubSiteId = (this._context.pageContext.legacyPageContext as any)?.hubSiteId
      this._currentHubSite = hubSiteId
        ? this.resolveHubSiteById(hubSiteId)
        : Promise.resolve(undefined)
    }
    return this._currentHubSite
  }
}
