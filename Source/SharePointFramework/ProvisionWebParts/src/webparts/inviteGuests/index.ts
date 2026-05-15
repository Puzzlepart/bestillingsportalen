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
import { GuestRequestService, SiteService } from '../../services'

export interface IInviteGuestsWebPartProps {
  title: string
  description: string
  displayMode: 'inline' | 'dialog'
  guestRequestListTitle: string
  guestRequestSiteUrl: string
}

export default class InviteGuestsWebPart extends BaseClientSideWebPart<IInviteGuestsWebPartProps> {
  private _service!: GuestRequestService
  private _siteService!: SiteService

  protected onInit(): Promise<void> {
    const targetSiteUrl =
      (this.properties.guestRequestSiteUrl || '').trim() || this.context.pageContext.web.absoluteUrl
    const adminSp: SPFI = spfi(targetSiteUrl).using(SPFx(this.context))
    this._service = new GuestRequestService(
      adminSp,
      this.properties.guestRequestListTitle || 'Guest Requests'
    )
    const currentSp: SPFI = spfi(this.context.pageContext.web.absoluteUrl).using(SPFx(this.context))
    this._siteService = new SiteService(currentSp)
    return Promise.resolve()
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
      siteUrl: this.context.pageContext.web.absoluteUrl,
      siteTitle: this.context.pageContext.web.title,
      currentUser: {
        loginName: this.context.pageContext.user.loginName,
        displayName: this.context.pageContext.user.displayName,
        email: this.context.pageContext.user.email
      },
      service: this._service,
      siteService: this._siteService,
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
