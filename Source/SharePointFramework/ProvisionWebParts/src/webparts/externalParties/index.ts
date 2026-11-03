import * as React from 'react'
import * as ReactDom from 'react-dom'
import { Version } from '@microsoft/sp-core-library'
import {
  type IPropertyPaneConfiguration,
  type IPropertyPaneField,
  PropertyPaneLabel,
  PropertyPaneTextField
} from '@microsoft/sp-property-pane'
import { BaseClientSideWebPart } from '@microsoft/sp-webpart-base'
import { spfi, SPFI, SPFx } from '@pnp/sp'

import * as strings from 'ProvisionWebPartsStrings'
import { ExternalParties } from '../../components/ExternalParties'
import type { IExternalPartiesProps, IWriteServices } from '../../components/ExternalParties/types'
import {
  AccessReaderService,
  ActivityLogService,
  DEFAULT_PART_TYPES,
  type IPartiesConfig,
  type IPartiesSiteInfo,
  resolvePartiesConfig,
  PartiesProvisioningService,
  PartiesService
} from '../../services/parties'

export interface IExternalPartiesWebPartProps {
  title: string
  description: string
  groupPrefix: string
  externalProjectManager: string
  /** JSON with the party types. Empty uses the defaults. */
  partTypes: string
  librariesFilter: string
  /** Libraries that can never be shared, separated by comma, semicolon or newline. */
  protectedLibraries: string
  navigationHeading: string
  activityLogUrl: string
  guestInvitationUrl: string
}

export default class ExternalPartiesWebPart extends BaseClientSideWebPart<IExternalPartiesWebPartProps> {
  private _sp!: SPFI
  /** Loaded with the property pane, so the code editor is not in the page bundle. */
  private _codeEditor?: typeof import('@pnp/spfx-property-controls/lib/PropertyFieldCodeEditor')
  private _partiesService!: PartiesService
  private _accessReader!: AccessReaderService

  protected async onInit(): Promise<void> {
    await super.onInit()
    this._sp = spfi(this.context.pageContext.web.absoluteUrl).using(SPFx(this.context))
    this._partiesService = new PartiesService(this._sp)
    this._accessReader = new AccessReaderService(this._sp)
  }

  /** The web part properties as configuration. Neutral defaults, see resolvePartiesConfig. */
  private get _config(): IPartiesConfig {
    return resolvePartiesConfig(this.properties)
  }

  /** Services that change SharePoint. Created when the site is known. */
  private _createWriteServices = (site: IPartiesSiteInfo): IWriteServices => {
    const config = this._config
    return {
      writer: new PartiesProvisioningService(this._sp, site),
      logger: new ActivityLogService(this._sp, site, config.activityLogUrl, config.activityLogTitle)
    }
  }

  public render(): void {
    // SharePoint chrome can pre-register an older Tabster instance without the
    // attrHandlers Map, which makes Fluent UI v9 crash. Same polyfill as in
    // InviteGuestsWebPart.
    const tabsterInstance = (
      window as unknown as { __tabsterInstance?: { attrHandlers?: Map<string, unknown> } }
    ).__tabsterInstance
    if (tabsterInstance && !tabsterInstance.attrHandlers) {
      tabsterInstance.attrHandlers = new Map()
    }

    const element: React.ReactElement<IExternalPartiesProps> = React.createElement(
      ExternalParties,
      {
        title: this.properties.title,
        description: this.properties.description,
        config: this._config,
        partiesService: this._partiesService,
        accessReader: this._accessReader,
        createWriteServices: this._createWriteServices
      }
    )
    ReactDom.render(element, this.domElement)
  }

  protected onDispose(): void {
    ReactDom.unmountComponentAtNode(this.domElement)
  }

  protected get dataVersion(): Version {
    return Version.parse('1.0')
  }

  protected get disableReactivePropertyChanges(): boolean {
    // Every property change would reload all access from SharePoint. Apply them in one go.
    return true
  }

  protected async loadPropertyPaneResources(): Promise<void> {
    this._codeEditor = await import(
      /* webpackChunkName: 'external-parties-property-pane' */
      '@pnp/spfx-property-controls/lib/PropertyFieldCodeEditor'
    )
  }

  /** JSON editor for the party types, or a plain text field until the editor is loaded. */
  private _partTypesField(): IPropertyPaneField<unknown> {
    if (!this._codeEditor) {
      return PropertyPaneTextField('partTypes', {
        label: strings.Parties.PartTypesLabel,
        description: strings.Parties.PartTypesDescription,
        multiline: true,
        rows: 8
      })
    }
    const { PropertyFieldCodeEditor, PropertyFieldCodeEditorLanguages } = this._codeEditor
    return PropertyFieldCodeEditor('partTypes', {
      key: 'partTypesCodeEditor',
      label: strings.Parties.PartTypesLabel,
      panelTitle: strings.Parties.PartTypesLabel,
      initialValue: this.properties.partTypes || JSON.stringify(DEFAULT_PART_TYPES, null, 2),
      language: PropertyFieldCodeEditorLanguages.JSON,
      properties: this.properties,
      onPropertyChange: this.onPropertyPaneFieldChanged.bind(this),
      deferredValidationTime: 500
    })
  }

  protected getPropertyPaneConfiguration(): IPropertyPaneConfiguration {
    return {
      pages: [
        {
          header: { description: strings.Parties.PropertyPaneDescription },
          displayGroupsAsAccordion: true,
          groups: [
            {
              groupName: strings.Parties.GroupGeneral,
              groupFields: [
                PropertyPaneTextField('title', { label: strings.Parties.TitleLabel }),
                PropertyPaneTextField('description', {
                  label: strings.Parties.DescriptionLabel,
                  multiline: true
                })
              ]
            },
            {
              groupName: strings.Parties.GroupParties,
              isCollapsed: true,
              groupFields: [
                PropertyPaneTextField('groupPrefix', {
                  label: strings.Parties.GroupPrefixLabel,
                  description: strings.Parties.GroupPrefixDescription
                }),
                PropertyPaneTextField('externalProjectManager', {
                  label: strings.Parties.ExternalProjectManagerLabel,
                  description: strings.Parties.ExternalProjectManagerDescription
                }),
                this._partTypesField(),
                PropertyPaneLabel('partTypesDescription', {
                  text: this._codeEditor ? strings.Parties.PartTypesDescription : ''
                })
              ]
            },
            {
              groupName: strings.Parties.GroupLibraries,
              isCollapsed: true,
              groupFields: [
                PropertyPaneTextField('protectedLibraries', {
                  label: strings.Parties.ProtectedLibrariesLabel,
                  description: strings.Parties.ProtectedLibrariesDescription,
                  multiline: true
                }),
                PropertyPaneTextField('librariesFilter', {
                  label: strings.Parties.LibrariesFilterLabel,
                  description: strings.Parties.LibrariesFilterDescription,
                  multiline: true
                })
              ]
            },
            {
              groupName: strings.Parties.GroupNavigation,
              isCollapsed: true,
              groupFields: [
                PropertyPaneTextField('navigationHeading', {
                  label: strings.Parties.NavigationHeadingLabel,
                  description: strings.Parties.NavigationHeadingDescription
                }),
                PropertyPaneTextField('guestInvitationUrl', {
                  label: strings.Parties.GuestInvitationUrlLabel,
                  description: strings.Parties.GuestInvitationUrlDescription
                })
              ]
            },
            {
              groupName: strings.Parties.GroupAdvanced,
              isCollapsed: true,
              groupFields: [
                PropertyPaneTextField('activityLogUrl', {
                  label: strings.Parties.ActivityLogUrlLabel,
                  description: strings.Parties.ActivityLogUrlDescription
                })
              ]
            }
          ]
        }
      ]
    }
  }
}
