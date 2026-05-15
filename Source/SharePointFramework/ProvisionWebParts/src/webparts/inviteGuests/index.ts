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

import * as strings from 'ProvisionWebPartsStrings'
import { InviteGuests } from '../../components/InviteGuests'
import type { IInviteGuestsProps } from '../../components/InviteGuests/types'
import { GuestRequestService } from '../../services/GuestRequestService'

export interface IInviteGuestsWebPartProps {
  title: string
  description: string
  displayMode: 'inline' | 'dialog'
  guestRequestListTitle: string
  guestRequestSiteUrl: string
}

export default class InviteGuestsWebPart extends BaseClientSideWebPart<IInviteGuestsWebPartProps> {
  private _service!: GuestRequestService

  protected onInit(): Promise<void> {
    const targetSiteUrl =
      (this.properties.guestRequestSiteUrl || '').trim() || this.context.pageContext.web.absoluteUrl
    const sp: SPFI = spfi(targetSiteUrl).using(SPFx(this.context))
    this._service = new GuestRequestService(
      sp,
      this.properties.guestRequestListTitle || 'Guest Requests'
    )
    return Promise.resolve()
  }

  public render(): void {
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
