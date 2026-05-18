import * as React from 'react'
import * as ReactDom from 'react-dom'
import { Version } from '@microsoft/sp-core-library'
import {
  type IPropertyPaneConfiguration,
  PropertyPaneChoiceGroup,
  PropertyPaneTextField
} from '@microsoft/sp-property-pane'
import { BaseClientSideWebPart } from '@microsoft/sp-webpart-base'
import { spfi, SPFI, SPFx } from '@pnp/sp'
import '@pnp/sp/webs'
import '@pnp/sp/lists'
import '@pnp/sp/items'
import '@pnp/sp/site-users/web'
import '@pnp/sp/site-groups/web'

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
  guestRequestListTitle: string
  guestRequestSiteUrl: string
}

export default class InviteGuestsWebPart extends BaseClientSideWebPart<IInviteGuestsWebPartProps> {
  private _service!: GuestRequestService
  private _siteService!: SiteService
  private _graphService!: GraphService

  protected async onInit(): Promise<void> {
    const targetSiteUrl =
      (this.properties.guestRequestSiteUrl || '').trim() || this.context.pageContext.web.absoluteUrl
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
      siteUrl: this.context.pageContext.web.absoluteUrl,
      siteTitle: this.context.pageContext.web.title,
      currentUser: {
        loginName: this.context.pageContext.user.loginName,
        displayName: this.context.pageContext.user.displayName,
        email: this.context.pageContext.user.email
      },
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
    return {
      pages: [
        {
          header: { description: strings.PropertyPaneDescription },
          groups: [
            {
              groupName: strings.BasicGroupName,
              groupFields: [
                PropertyPaneTextField('title', { label: strings.TitleFieldLabel }),
                PropertyPaneTextField('description', {
                  label: strings.DescriptionFieldLabel,
                  multiline: true
                }),
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
                }),
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
                }),
                PropertyPaneTextField('guestRequestSiteUrl', {
                  label: strings.GuestRequestSiteUrlFieldLabel,
                  description: strings.GuestRequestSiteUrlFieldDescription
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
