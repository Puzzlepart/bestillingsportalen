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
import * as strings from 'ProvisionWebPartsStrings'
import { IProvisionRequestItem } from '../models/IProvisionRequestItem'
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
 * Service handling all data operations for the `ProjectProvision` web part.
 * Ported from PP365's `DataAdapter` provisioning slice, rewritten for
 * PnPjs v4: instead of the v3 `Web([sp.web, url])` tuple pattern, a
 * separate `SPFI` instance is created (and cached) per target site.
 */
export class ProvisionService {
  private _webs = new Map<string, SPFI>()
  private _currentHubSite: Promise<{ hubSiteId: string; title: string; url: string } | null>

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
    } catch (error) {
      return false
    }
  }

  /**
   * Checks if the current user has read access to the provisioning site.
   */
  public async hasProvisionSiteAccess(provisionUrl: string): Promise<boolean> {
    try {
      return await this._spfi(provisionUrl).web.currentUserHasPermissions(
        PermissionKind.ViewListItems
      )
    } catch (error) {
      return false
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
      AllowEmailAddresses: true,
      PrincipalSource: 15,
      PrincipalType: 1
    })
    const items = profiles.map((profile) => ({
      text: profile.DisplayText,
      secondaryText: profile.EntityData.Email,
      tertiaryText: profile.EntityData.Title,
      optionalText: profile.EntityData.Department,
      imageUrl: `/_layouts/15/userphoto.aspx?AccountName=${profile.EntityData.Email}&size=L`,
      id: profile.Key
    }))
    return items.filter(
      ({ secondaryText }) => !selectedItems?.some((item) => item.secondaryText === secondaryText)
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

  public async getProvisionUsers(
    users: IProvisionPersona[],
    provisionUrl: string
  ): Promise<Promise<number | null>[]> {
    try {
      const provisionWeb = this._spfi(provisionUrl).web
      return users.map(async (user) => {
        try {
          const result = await provisionWeb.ensureUser(user.secondaryText)
          return result?.Id ?? null
        } catch (error) {
          console.warn(
            `(ProvisionService) (getProvisionUsers) ensureUser failed for ${user.secondaryText}:`,
            error
          )
          return null
        }
      })
    } catch (error) {
      console.warn(
        '(ProvisionService) (getProvisionUsers) Failed to resolve provision site:',
        error
      )
      return []
    }
  }

  public async addProvisionRequests(
    properties: IProvisionRequestItem,
    provisionUrl: string
  ): Promise<boolean> {
    try {
      const provisionRequestsList =
        this._spfi(provisionUrl).web.lists.getByTitle('Provisioning Requests')
      await provisionRequestsList.items.add(properties)
      return true
    } catch (error) {
      return false
    }
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
    } catch (error) {
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
    try {
      return await this._spfi().site.exists(siteUrl)
    } catch (error) {
      return false
    }
  }

  public async loadTeamsConfig(provisionUrl: string): Promise<any | null> {
    try {
      const file = this._spfi(provisionUrl)
        .web.getFolderByServerRelativePath('SiteAssets')
        .files.getByUrl('TeamsAppConfig.json')
      const content = await file.getText()
      return JSON.parse(content)
    } catch (error) {
      console.log('TeamsAppConfig.json not found or error loading:', error.message)
      return null
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
  ): Promise<{ hubSiteId: string; title: string; url: string } | null> {
    const normalizedId = normalizeHubSiteId(hubSiteId)
    if (!normalizedId) return null
    try {
      const webAbsoluteUrl = this._context.pageContext.web.absoluteUrl
      const response = await fetch(`${webAbsoluteUrl}/_api/HubSites/GetById('${normalizedId}')`, {
        method: 'GET',
        headers: { Accept: 'application/json;odata=nometadata' },
        credentials: 'include'
      })
      if (!response.ok) return null
      const hubSite = await response.json()
      return {
        hubSiteId: normalizeHubSiteId(hubSite.ID) || normalizedId,
        title: hubSite.Title || '',
        url: hubSite.SiteUrl || ''
      }
    } catch (error) {
      console.warn('Failed to resolve hub site by ID:', error)
      return null
    }
  }

  /**
   * Resolves the hub site of the CURRENT site (via
   * `legacyPageContext.hubSiteId`), or null when the current site is not
   * associated with a hub. The result is cached for the lifetime of the
   * service. Replaces PP365's `portalDataService.url`, which pointed at the
   * portfolio hub the web part was installed on.
   */
  public getCurrentHubSite(): Promise<{ hubSiteId: string; title: string; url: string } | null> {
    if (!this._currentHubSite) {
      const hubSiteId = (this._context.pageContext.legacyPageContext as any)?.hubSiteId
      this._currentHubSite = hubSiteId ? this.resolveHubSiteById(hubSiteId) : Promise.resolve(null)
    }
    return this._currentHubSite
  }
}
