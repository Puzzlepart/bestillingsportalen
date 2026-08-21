import * as React from 'react'
import * as ReactDom from 'react-dom'
import { Version } from '@microsoft/sp-core-library'
import {
  type IPropertyPaneConfiguration,
  PropertyPaneChoiceGroup,
  PropertyPaneDropdown,
  PropertyPaneTextField,
  PropertyPaneToggle
} from '@microsoft/sp-property-pane'
import { BaseClientSideWebPart } from '@microsoft/sp-webpart-base'
import { PropertyFieldOrder } from '@pnp/spfx-property-controls/lib/PropertyFieldOrder'
import { spfi, SPFI, SPFx } from '@pnp/sp'
import '@pnp/sp/webs'
import '@pnp/sp/sites'
import '@pnp/sp/lists'
import '@pnp/sp/items'
import '@pnp/sp/site-users/web'
import '@pnp/sp/site-groups/web'
import '@pnp/sp/security'

import * as strings from 'ProvisionWebPartsStrings'
import { InviteGuests } from '../../components/InviteGuests'
import type { IInviteGuestsProps } from '../../components/InviteGuests/types'
import { GraphService, GuestRequestService, SiteService } from '../../services'

export interface IInviteGuestsWebPartProps {
  title: string
  description: string
  displayMode: 'inline' | 'dialog'
  inviteMode: 'Single' | 'Multi'
  inviteAccessLevel: 'Owner' | 'Member' | 'Anyone'
  perGuestProfileMode: 'Disabled' | 'Optional' | 'Enforced'
  perGuestRoleMode: 'Disabled' | 'Optional' | 'Enforced'
  // Locked to guest-safe roles — 'Member' is the standard M365 guest model
  // (labelled "Gjest"); guests can never be group owners (see
  // models/IGuestRequest.ts). Stored 'Visitor'/'Owner' values from older
  // versions are clamped in render().
  defaultM365GroupRole: 'None' | 'Member'
  defaultSpGroupAction: 'None' | 'AddToExisting' | 'CreateNew'
  defaultSpGroupName: string
  presetSpGroupName: string
  showSpActionNone: boolean
  showSpActionAddToExisting: boolean
  showSpActionCreateNew: boolean
  showSpActionPreset: boolean
  spGroupActionOrder: { key: string; text: string }[]
  defaultSpPermissionLevel: 'Read' | 'Contribute' | 'Edit' | 'Full Control'
  autoSelectVisitorGroup: boolean
  lockM365GroupRole: boolean
  lockSpGroupAction: boolean
  showAccessPreview: boolean
  showStatusSummary: boolean
  showCopyRedeemUrl: boolean
  showRetryButton: boolean
  showColumnM365Role: boolean
  showColumnSPGroupAction: boolean
  showColumnSPGroupName: boolean
  showColumnSPPermissionLevel: boolean
  showM365GroupRoleSection: boolean
  showSPGroupSection: boolean
  hiddenSpGroups: string
  allowedSpGroups: string
  guestRequestListTitle: string
  guestRequestSiteUrl: string
}

export default class InviteGuestsWebPart extends BaseClientSideWebPart<IInviteGuestsWebPartProps> {
  private _service!: GuestRequestService
  private _siteService!: SiteService
  private _graphService!: GraphService

  /**
   * Default location of the Guest Requests list when guestRequestSiteUrl is
   * blank. /sites/bestillingsportalen is the solution-wide convention (the
   * requestsSiteAlias deploy default; the Teams app hardcodes the same URL).
   * Falling back to the CURRENT site only ever worked when the web part sat on
   * the portal itself — everywhere else it pointed at a site without the list.
   */
  private get _defaultGuestRequestSiteUrl(): string {
    return new URL('/sites/bestillingsportalen', this.context.pageContext.web.absoluteUrl).href
  }

  protected async onInit(): Promise<void> {
    const targetSiteUrl =
      (this.properties.guestRequestSiteUrl || '').trim() || this._defaultGuestRequestSiteUrl
    const adminSp: SPFI = spfi(targetSiteUrl).using(SPFx(this.context))
    this._service = new GuestRequestService(
      adminSp,
      this.properties.guestRequestListTitle || 'Guest Requests'
    )
    const currentSp: SPFI = spfi(this.context.pageContext.web.absoluteUrl).using(SPFx(this.context))
    this._siteService = new SiteService(currentSp)
    const graphClient = await this.context.msGraphClientFactory.getClient('3')
    this._graphService = new GraphService(graphClient)
  }

  public render(): void {
    // SharePoint chrome can pre-register an older Tabster instance on
    // window.__tabsterInstance that lacks the attrHandlers Map (added in
    // tabster v8.8). Our bundled Fluent UI v9 components then crash inside
    // getModalizer/getGroupper with "Cannot read properties of undefined
    // (reading 'set')". Idempotent polyfill so subsequent renders are no-ops.
    const tabsterInstance = (
      window as unknown as { __tabsterInstance?: { attrHandlers?: Map<string, unknown> } }
    ).__tabsterInstance
    if (tabsterInstance && !tabsterInstance.attrHandlers) {
      tabsterInstance.attrHandlers = new Map()
    }

    const element: React.ReactElement<IInviteGuestsProps> = React.createElement(InviteGuests, {
      title: this.properties.title,
      description: this.properties.description,
      displayMode: this.properties.displayMode || 'dialog',
      inviteMode: this.properties.inviteMode || 'Multi',
      inviteAccessLevel: this.properties.inviteAccessLevel || 'Owner',
      perGuestProfileMode: this.properties.perGuestProfileMode || 'Optional',
      perGuestRoleMode: this.properties.perGuestRoleMode || 'Optional',
      // Clamp pre-lock persisted values (Visitor/Owner) to the guest role.
      defaultM365GroupRole: this.properties.defaultM365GroupRole === 'None' ? 'None' : 'Member',
      defaultSpGroupAction: this.properties.defaultSpGroupAction || 'AddToExisting',
      defaultSpGroupName: this.properties.defaultSpGroupName || '',
      presetSpGroupName: this.properties.presetSpGroupName || '',
      showSpActionNone: this.properties.showSpActionNone !== false,
      showSpActionAddToExisting: this.properties.showSpActionAddToExisting !== false,
      showSpActionCreateNew: this.properties.showSpActionCreateNew !== false,
      showSpActionPreset: this.properties.showSpActionPreset !== false,
      // PropertyFieldOrder stores an ordered array of { key, text }; the React
      // layer consumes a CSV of keys (parsed in useInviteDrawer), so flatten it.
      spGroupActionOrder: (this.properties.spGroupActionOrder || []).map((i) => i.key).join(','),
      defaultSpPermissionLevel: this.properties.defaultSpPermissionLevel || 'Read',
      autoSelectVisitorGroup: this.properties.autoSelectVisitorGroup !== false,
      lockM365GroupRole: this.properties.lockM365GroupRole === true,
      lockSpGroupAction: this.properties.lockSpGroupAction === true,
      showAccessPreview: this.properties.showAccessPreview !== false,
      showStatusSummary: this.properties.showStatusSummary !== false,
      showCopyRedeemUrl: this.properties.showCopyRedeemUrl !== false,
      showRetryButton: this.properties.showRetryButton !== false,
      showColumnM365Role: this.properties.showColumnM365Role === true,
      showColumnSPGroupAction: this.properties.showColumnSPGroupAction === true,
      showColumnSPGroupName: this.properties.showColumnSPGroupName === true,
      showColumnSPPermissionLevel: this.properties.showColumnSPPermissionLevel === true,
      showM365GroupRoleSection: this.properties.showM365GroupRoleSection !== false,
      showSPGroupSection: this.properties.showSPGroupSection !== false,
      hiddenSpGroups: this.properties.hiddenSpGroups || '',
      allowedSpGroups: this.properties.allowedSpGroups || '',
      siteUrl: this.context.pageContext.web.absoluteUrl,
      siteTitle: this.context.pageContext.web.title,
      service: this._service,
      siteService: this._siteService,
      graphService: this._graphService,
      themeProvider: this.context.serviceScope
    })
    ReactDom.render(element, this.domElement)
  }

  protected onDispose(): void {
    ReactDom.unmountComponentAtNode(this.domElement)
  }

  protected get dataVersion(): Version {
    return Version.parse('1.0')
  }

  protected getPropertyPaneConfiguration(): IPropertyPaneConfiguration {
    const defaultSpGroupAction = this.properties.defaultSpGroupAction || 'AddToExisting'

    // Build the ordered item list for PropertyFieldOrder: preserve the admin's
    // stored order, append any missing known keys, and (re)apply localized text
    // so the list always shows all four options in the current UI language.
    const spActionKeys = ['None', 'AddToExisting', 'CreateNew', 'Preset']
    const spActionText = (key: string): string => {
      switch (key) {
        case 'None':
          return strings.SPGroupActionNoneLabel
        case 'AddToExisting':
          return strings.SPGroupActionExistingLabel
        case 'CreateNew':
          return strings.SPGroupActionNewLabel
        case 'Preset':
          return strings.SPGroupActionPresetLabel
        default:
          return key
      }
    }
    const storedOrderKeys = (this.properties.spGroupActionOrder || [])
      .map((i) => i.key)
      .filter((k) => spActionKeys.indexOf(k) !== -1)
    const orderedKeys = [
      ...storedOrderKeys,
      ...spActionKeys.filter((k) => storedOrderKeys.indexOf(k) === -1)
    ]
    const spActionOrderItems = orderedKeys.map((k) => ({ key: k, text: spActionText(k) }))

    return {
      pages: [
        {
          header: { description: strings.PropertyPaneDescription },
          displayGroupsAsAccordion: true,
          groups: [
            {
              groupName: strings.GeneralGroupName,
              groupFields: [
                PropertyPaneTextField('title', { label: strings.TitleFieldLabel }),
                PropertyPaneTextField('description', {
                  label: strings.DescriptionFieldLabel,
                  multiline: true
                })
              ]
            },
            {
              groupName: strings.InviteSettingsGroupName,
              groupFields: [
                PropertyPaneChoiceGroup('displayMode', {
                  label: strings.DisplayModeFieldLabel,
                  options: [
                    { key: 'inline', text: strings.DisplayModeInlineLabel },
                    { key: 'dialog', text: strings.DisplayModeDialogLabel }
                  ]
                }),
                PropertyPaneChoiceGroup('inviteMode', {
                  label: strings.InviteModeFieldLabel,
                  options: [
                    { key: 'Single', text: strings.InviteModeSingleLabel },
                    { key: 'Multi', text: strings.InviteModeMultiLabel }
                  ]
                }),
                PropertyPaneChoiceGroup('inviteAccessLevel', {
                  label: strings.InviteAccessLevelFieldLabel,
                  options: [
                    { key: 'Owner', text: strings.InviteAccessLevelOwnerLabel },
                    { key: 'Member', text: strings.InviteAccessLevelMemberLabel },
                    { key: 'Anyone', text: strings.InviteAccessLevelAnyoneLabel }
                  ]
                })
              ]
            },
            {
              groupName: strings.DefaultsGroupName,
              isCollapsed: true,
              groupFields: [
                PropertyPaneDropdown('defaultM365GroupRole', {
                  label: strings.DefaultM365GroupRoleFieldLabel,
                  options: [
                    { key: 'None', text: strings.M365GroupRoleNoneLabel },
                    { key: 'Member', text: strings.M365GroupRoleMemberLabel }
                  ]
                }),
                PropertyPaneDropdown('defaultSpGroupAction', {
                  label: strings.DefaultSpGroupActionFieldLabel,
                  options: [
                    { key: 'None', text: strings.SPGroupActionNoneLabel },
                    { key: 'AddToExisting', text: strings.SPGroupActionExistingLabel },
                    { key: 'CreateNew', text: strings.SPGroupActionNewLabel }
                  ]
                }),
                PropertyPaneTextField('defaultSpGroupName', {
                  label: strings.DefaultSpGroupNameFieldLabel,
                  description: strings.DefaultSpGroupNameFieldDescription,
                  disabled: defaultSpGroupAction !== 'AddToExisting'
                }),
                PropertyPaneTextField('presetSpGroupName', {
                  label: strings.PresetSpGroupNameFieldLabel,
                  description: strings.PresetSpGroupNameFieldDescription
                }),
                PropertyPaneDropdown('defaultSpPermissionLevel', {
                  label: strings.DefaultSpPermissionLevelFieldLabel,
                  options: [
                    { key: 'Read', text: strings.SPPermissionRead },
                    { key: 'Contribute', text: strings.SPPermissionContribute },
                    { key: 'Edit', text: strings.SPPermissionEdit },
                    { key: 'Full Control', text: strings.SPPermissionFullControl }
                  ],
                  disabled: defaultSpGroupAction !== 'CreateNew'
                }),
                PropertyPaneToggle('autoSelectVisitorGroup', {
                  label: strings.AutoSelectVisitorGroupFieldLabel,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff,
                  disabled: defaultSpGroupAction !== 'AddToExisting'
                }),
                PropertyPaneToggle('lockM365GroupRole', {
                  label: strings.LockM365GroupRoleFieldLabel,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                }),
                PropertyPaneToggle('lockSpGroupAction', {
                  label: strings.LockSpGroupActionFieldLabel,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                })
              ]
            },
            {
              groupName: strings.SpGroupOptionsGroupName,
              isCollapsed: true,
              groupFields: [
                PropertyPaneToggle('showSpActionNone', {
                  label: strings.ShowSpActionNoneFieldLabel,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                }),
                PropertyPaneToggle('showSpActionAddToExisting', {
                  label: strings.ShowSpActionExistingFieldLabel,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                }),
                PropertyPaneToggle('showSpActionCreateNew', {
                  label: strings.ShowSpActionNewFieldLabel,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                }),
                PropertyPaneToggle('showSpActionPreset', {
                  label: strings.ShowSpActionPresetFieldLabel,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                }),
                PropertyFieldOrder('spGroupActionOrder', {
                  key: 'spGroupActionOrder',
                  label: strings.SpGroupActionOrderFieldLabel,
                  items: spActionOrderItems,
                  textProperty: 'text',
                  properties: this.properties,
                  onPropertyChange: this.onPropertyPaneFieldChanged,
                  removeArrows: false,
                  disableDragAndDrop: false
                })
              ]
            },
            {
              groupName: strings.DrawerShowHideGroupName,
              isCollapsed: true,
              groupFields: [
                PropertyPaneToggle('showAccessPreview', {
                  label: strings.ShowAccessPreviewFieldLabel,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                }),
                PropertyPaneToggle('showM365GroupRoleSection', {
                  label: strings.ShowM365GroupRoleSectionFieldLabel,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                }),
                PropertyPaneToggle('showSPGroupSection', {
                  label: strings.ShowSPGroupSectionFieldLabel,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                })
              ]
            },
            {
              groupName: strings.StatusShowHideGroupName,
              isCollapsed: true,
              groupFields: [
                PropertyPaneToggle('showStatusSummary', {
                  label: strings.ShowStatusSummaryFieldLabel,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                }),
                PropertyPaneToggle('showCopyRedeemUrl', {
                  label: strings.ShowCopyRedeemUrlFieldLabel,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                }),
                PropertyPaneToggle('showRetryButton', {
                  label: strings.ShowRetryButtonFieldLabel,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                }),
                PropertyPaneToggle('showColumnM365Role', {
                  label: strings.ShowColumnM365RoleFieldLabel,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                }),
                PropertyPaneToggle('showColumnSPGroupAction', {
                  label: strings.ShowColumnSPGroupActionFieldLabel,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                }),
                PropertyPaneToggle('showColumnSPGroupName', {
                  label: strings.ShowColumnSPGroupNameFieldLabel,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                }),
                PropertyPaneToggle('showColumnSPPermissionLevel', {
                  label: strings.ShowColumnSPPermissionLevelFieldLabel,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                })
              ]
            },
            {
              groupName: strings.PerGuestGroupName,
              isCollapsed: true,
              groupFields: [
                PropertyPaneChoiceGroup('perGuestProfileMode', {
                  label: strings.PerGuestProfileModeFieldLabel,
                  options: [
                    { key: 'Disabled', text: strings.FeatureModeDisabledLabel },
                    { key: 'Optional', text: strings.FeatureModeOptionalLabel },
                    { key: 'Enforced', text: strings.FeatureModeEnforcedLabel }
                  ]
                }),
                PropertyPaneChoiceGroup('perGuestRoleMode', {
                  label: strings.PerGuestRoleModeFieldLabel,
                  options: [
                    { key: 'Disabled', text: strings.FeatureModeDisabledLabel },
                    { key: 'Optional', text: strings.FeatureModeOptionalLabel },
                    { key: 'Enforced', text: strings.FeatureModeEnforcedLabel }
                  ]
                })
              ]
            },
            {
              groupName: strings.AdvancedGroupName,
              isCollapsed: true,
              groupFields: [
                PropertyPaneTextField('allowedSpGroups', {
                  label: strings.AllowedSpGroupsFieldLabel,
                  description: strings.AllowedSpGroupsFieldDescription,
                  multiline: true
                }),
                PropertyPaneTextField('hiddenSpGroups', {
                  label: strings.HiddenSpGroupsFieldLabel,
                  description: strings.HiddenSpGroupsFieldDescription,
                  multiline: true
                }),
                PropertyPaneTextField('guestRequestSiteUrl', {
                  label: strings.GuestRequestSiteUrlFieldLabel,
                  description: strings.GuestRequestSiteUrlFieldDescription,
                  placeholder: this._defaultGuestRequestSiteUrl
                }),
                PropertyPaneTextField('guestRequestListTitle', {
                  label: strings.GuestRequestListTitleFieldLabel,
                  description: strings.GuestRequestListTitleFieldDescription
                })
              ]
            }
          ]
        }
      ]
    }
  }
}
