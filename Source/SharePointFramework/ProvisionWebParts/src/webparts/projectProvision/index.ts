/* eslint-disable no-console */

import { Version } from '@microsoft/sp-core-library'
import {
  IPropertyPaneConfiguration,
  PropertyPaneDropdown,
  PropertyPaneLabel,
  PropertyPaneTextField,
  PropertyPaneToggle
} from '@microsoft/sp-property-pane'
import { BaseClientSideWebPart } from '@microsoft/sp-webpart-base'
import { spfi, SPFI, SPFx } from '@pnp/sp'
import * as strings from 'ProvisionWebPartsStrings'
import {
  DEFAULT_PROVISION_ACCESS_GROUP,
  IProjectProvisionProps,
  IProvisionField,
  ITypeFieldConfiguration,
  ProjectProvision
} from '../../components/ProjectProvision'
import { PropertyFieldMessage } from '@pnp/spfx-property-controls/lib/PropertyFieldMessage'
import { PropertyPanePropertyEditor } from '@pnp/spfx-property-controls/lib/PropertyPanePropertyEditor'
import {
  PropertyFieldCollectionData,
  CustomCollectionFieldType
} from '@pnp/spfx-property-controls/lib/PropertyFieldCollectionData'
import { PropertyFieldMultiSelect } from '@pnp/spfx-property-controls/lib/PropertyFieldMultiSelect'
import { getDefaultFields } from '../../components/ProjectProvision/getDefaultFields'
import { getDefaultTypeFieldConfigurations } from '../../components/ProjectProvision/getFieldsForType'
import * as React from 'react'
import * as ReactDom from 'react-dom'
import { Dropdown, Option, IdPrefixProvider, FluentProvider } from '@fluentui/react-components'
import { customLightTheme } from '../../utils/theme'
import { format } from '../../utils/format'
import { ProvisionService } from '../../services/ProvisionService'
import {
  DEFAULT_PROVISION_URL,
  getRememberedInstanceUrl,
  IProvisionInstance,
  rememberInstanceUrl,
  resolveProvisionUrl,
  sameInstanceUrl
} from '../../services/provisionInstances'
import { InstancePicker } from '../../components/ProjectProvision/InstancePicker'

const DEFAULT_PROVISION_TYPES = [
  { key: 'Prosjektområde', text: strings.Provision.ProjectAreaType },
  { key: 'Viva Engage Community', text: strings.Provision.VivaEngageCommunityType },
  { key: 'Microsoft Teams Team', text: strings.Provision.MicrosoftTeamsTeamType }
]

export default class ProjectProvisionWebPart extends BaseClientSideWebPart<IProjectProvisionProps> {
  private _sp: SPFI
  private _provisionService: ProvisionService
  private _defaultFields = getDefaultFields()
  private _defaultTypeFieldConfigurations = getDefaultTypeFieldConfigurations()
  private _provisionTypes: Array<{ key: string; text: string; disabled?: boolean }> = []
  private _instances: IProvisionInstance[] = []
  private _accessibleInstances: IProvisionInstance[] = []
  private _instanceResolved = false
  private _initialProperties: IProjectProvisionProps
  // The effective site URL. Kept OUT of this.properties: on SharePoint pages
  // the property bag is persisted on page save, and writing the resolved URL
  // there would silently freeze the registry value into the page.
  private _resolvedProvisionUrl = ''

  public async render(): Promise<void> {
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

    let element: React.ReactElement
    if (!this._instanceResolved) {
      // The user has access to several instances and no remembered choice —
      // let them pick before any instance-specific data is loaded.
      element = React.createElement(InstancePicker, {
        instances: this._accessibleInstances,
        onSelect: (url: string) => this._switchInstance(url)
      })
    } else {
      let hasProjectProvisionAccess = true
      if (this.properties.requireProvisionAccess) {
        try {
          hasProjectProvisionAccess = await this._provisionService.isUserInGroup(
            this.properties.provisionAccessGroupTitle || DEFAULT_PROVISION_ACCESS_GROUP
          )
        } catch {
          hasProjectProvisionAccess = false
        }
      }

      element = React.createElement(ProjectProvision, {
        // Remount on instance switch: the data-fetch effect only depends on
        // `refetch`, so a fresh mount is what forces a refetch and resets state.
        key: this._resolvedProvisionUrl,
        manifestId: this.manifest.id,
        ...this.properties,
        provisionUrl: this._resolvedProvisionUrl,
        provisionInstances: this._accessibleInstances,
        onSwitchInstance:
          this._accessibleInstances.length > 1
            ? (url: string) => this._switchInstance(url)
            : undefined,
        hasProjectProvisionAccess,
        provisionService: this._provisionService,
        displayMode: this.displayMode,
        sp: this._sp,
        pageContext: this.context.pageContext,
        webAbsoluteUrl: this.context.pageContext.web.absoluteUrl
      })
    }
    ReactDom.render(element, this.domElement)
  }

  protected onDispose(): void {
    ReactDom.unmountComponentAtNode(this.domElement)
  }

  protected get dataVersion(): Version {
    return Version.parse('1.0')
  }

  private mergeFields(
    userFields: IProvisionField[],
    defaultFields: IProvisionField[]
  ): IProvisionField[] {
    const userFieldNames = userFields.map((field) => field.fieldName)
    return [
      ...userFields,
      ...defaultFields.filter((defaultField) => !userFieldNames.includes(defaultField.fieldName))
    ]
  }

  private mergeTypeConfigurations(
    userConfigurations: ITypeFieldConfiguration[],
    defaultConfigurations: ITypeFieldConfiguration[]
  ): ITypeFieldConfiguration[] {
    const userTypeNames = userConfigurations.map((config) => config.typeName)
    return [
      ...userConfigurations,
      ...defaultConfigurations.filter(
        (defaultConfig) => !userTypeNames.includes(defaultConfig.typeName)
      )
    ]
  }

  public async onInit(): Promise<void> {
    this._sp = spfi(this.context.pageContext.web.absoluteUrl).using(SPFx(this.context))
    this._provisionService = new ProvisionService(this.context)

    const isTeams = !!this.context.sdks?.microsoftTeams
    if (isTeams) {
      this.properties.renderMode = 'inline'
      this.properties.isTeamsContext = true
      if (!this.properties.drawerSize) this.properties.drawerSize = 'full'
    }

    // Pristine snapshot (taken after the Teams-mode flags) restored on every
    // instance switch, so one instance's Object.assign-ed TeamsAppConfig does
    // not leak into the next.
    this._initialProperties = { ...this.properties }
    this._instances = await this._provisionService.getTenantProvisionInstances()

    if (!isTeams || this._instances.length <= 1) {
      await this._applyProvisionUrl(
        resolveProvisionUrl(this.properties.provisionUrl, this._instances, isTeams)
      )
      this._instanceResolved = true
      return
    }

    // Multiple registry entries in Teams: offer only the instances the user
    // can actually access, and show the picker only when there are several.
    const accessResults = await Promise.all(
      this._instances.map((instance) => this._provisionService.getProvisionSiteAccess(instance.url))
    )
    this._accessibleInstances = this._instances.filter(
      (_, index) => accessResults[index] === 'granted'
    )

    if (this._accessibleInstances.length === 0) {
      // Open the tenant default; the component's own access check renders the
      // accurate access-denied / not-found message.
      await this._applyProvisionUrl(this._instances[0].url)
      this._instanceResolved = true
    } else if (this._accessibleInstances.length === 1) {
      await this._applyProvisionUrl(this._accessibleInstances[0].url)
      this._instanceResolved = true
    } else {
      const remembered = getRememberedInstanceUrl()
      const match = this._accessibleInstances.find((instance) =>
        sameInstanceUrl(instance.url, remembered)
      )
      if (match) {
        await this._applyProvisionUrl(match.url)
        this._instanceResolved = true
      }
      // else: render() shows the instance picker. TeamsAppConfig and the
      // provision types load once the user picks (inside _applyProvisionUrl).
    }
  }

  /**
   * Applies the effective site URL: restores the pristine property snapshot,
   * loads `TeamsAppConfig.json` from the instance (Teams only), re-merges
   * fields/type configurations (the config may carry them) and reloads the
   * provision types. Runs on init and on every instance switch.
   */
  private async _applyProvisionUrl(url: string): Promise<void> {
    for (const key of Object.keys(this.properties)) {
      if (!(key in this._initialProperties)) delete (this.properties as any)[key]
    }
    Object.assign(this.properties, this._initialProperties)
    this._resolvedProvisionUrl = url

    if (this.context.sdks?.microsoftTeams && url) {
      try {
        const teamsConfig = await this._provisionService.loadTeamsConfig(url)
        if (teamsConfig) {
          Object.assign(this.properties, teamsConfig)
          console.log('Loaded Teams configuration from TeamsAppConfig.json')
        }
      } catch (error) {
        console.warn('Failed to load Teams configuration:', error)
      }
    }

    this.properties.fields = this.mergeFields(this.properties.fields || [], this._defaultFields)
    this.properties.typeFieldConfigurations = this.mergeTypeConfigurations(
      this.properties.typeFieldConfigurations || [],
      this._defaultTypeFieldConfigurations
    )

    await this.loadProvisionTypes()
  }

  private _switchInstance(url: string): void {
    rememberInstanceUrl(url)
    void this._applyProvisionUrl(url).then(() => {
      this._instanceResolved = true
      return this.render()
    })
  }

  private async loadProvisionTypes(): Promise<void> {
    if (!this._resolvedProvisionUrl) {
      this._provisionTypes = [...DEFAULT_PROVISION_TYPES]
      return
    }

    try {
      const types = await this._provisionService.getProvisionTypes(this._resolvedProvisionUrl)
      const availableTypeNames = types.map((type: any) => type.title)
      const mergedTypes = new Map<string, { key: string; text: string; disabled?: boolean }>()

      DEFAULT_PROVISION_TYPES.forEach((defaultType) => {
        mergedTypes.set(defaultType.key, {
          key: defaultType.key,
          text: defaultType.text,
          disabled: !availableTypeNames.includes(defaultType.key)
        })
      })

      types.forEach((type: any) => {
        if (!mergedTypes.has(type.title)) {
          mergedTypes.set(type.title, {
            key: type.title,
            text: type.title,
            disabled: false
          })
        } else {
          const existing = mergedTypes.get(type.title)!
          existing.disabled = false
        }
      })

      this._provisionTypes = Array.from(mergedTypes.values())
    } catch (error) {
      console.warn('Failed to load provision types, using defaults:', error)
      this._provisionTypes = [...DEFAULT_PROVISION_TYPES]
    }
  }

  public getPropertyPaneConfiguration(): IPropertyPaneConfiguration {
    const propertiesWithDefaults = { ...ProjectProvision.defaultProps, ...this.properties }

    const fieldsValue = [...(this.properties.fields || [])]
    const typeFieldConfigurationsValue = [...(this.properties.typeFieldConfigurations || [])]

    return {
      pages: [
        {
          header: {
            description: strings.Provision.WebPartDescription
          },
          displayGroupsAsAccordion: true,
          groups: [
            {
              groupName: strings.GeneralGroupName,
              groupFields: [
                PropertyPaneDropdown('renderMode', {
                  label: strings.Provision.RenderModeFieldLabel,
                  options: [
                    { key: 'button', text: strings.Provision.RenderModeButton },
                    { key: 'inline', text: strings.Provision.RenderModeInline }
                  ],
                  selectedKey: propertiesWithDefaults.renderMode ?? 'button'
                }),
                PropertyPaneDropdown('drawerSize', {
                  label: strings.Provision.DrawerSizeFieldLabel,
                  options: [
                    { key: 'medium', text: strings.Provision.DrawerSizeMedium },
                    { key: 'full', text: strings.Provision.DrawerSizeFull }
                  ],
                  selectedKey: propertiesWithDefaults.drawerSize ?? 'medium',
                  disabled: propertiesWithDefaults.renderMode === 'inline'
                }),
                PropertyPaneTextField('buttonLabel', {
                  label: strings.Provision.ButtonLabelFieldLabel,
                  description: strings.Provision.ButtonLabelFieldDescription,
                  placeholder: strings.Provision.ProvisionButtonLabel,
                  disabled: propertiesWithDefaults.renderMode === 'inline'
                }),
                PropertyPaneToggle('autoOwner', {
                  label: strings.Provision.AutoOwnerFieldLabel,
                  checked: propertiesWithDefaults.autoOwner,
                  onText: strings.Provision.AutoOwnerOnText,
                  offText: strings.Provision.AutoOwnerOffText
                }),
                PropertyPaneLabel('autoOwnerLabel', {
                  text: strings.Provision.AutoOwnerFieldDescription
                })
              ]
            },
            {
              groupName: strings.Provision.AppearanceGroupName,
              groupFields: [
                PropertyPaneDropdown('siteTypeRenderMode', {
                  label: strings.Provision.SiteTypeRenderModeFieldLabel,
                  options: [
                    { key: 'cardNormal', text: strings.Provision.SiteTypeRenderModeCardNormal },
                    { key: 'cardMinimal', text: strings.Provision.SiteTypeRenderModeCardMinimal },
                    { key: 'dropdown', text: strings.Provision.SiteTypeRenderModeDropdown }
                  ],
                  selectedKey: propertiesWithDefaults.siteTypeRenderMode ?? 'cardNormal'
                }),
                PropertyPaneDropdown('expirationDateMode', {
                  label: strings.Provision.ExpirationDateModeFieldLabel,
                  options: [
                    { key: 'date', text: strings.Provision.ExpirationDateModeDate },
                    {
                      key: 'monthDropdown',
                      text: strings.Provision.ExpirationDateModeMonthDropdown
                    }
                  ],
                  selectedKey: propertiesWithDefaults.expirationDateMode ?? 'date'
                })
              ]
            },
            {
              groupName: strings.Provision.TitlesAndDescriptionsGroupName,
              isCollapsed: true,
              groupFields: [
                PropertyPaneTextField('level0Header', {
                  label: strings.Provision.Level0HeaderFieldLabel,
                  description: strings.Provision.Level0HeaderFieldDescription,
                  placeholder: strings.Provision.DrawerLevel0HeaderText
                }),
                PropertyPaneTextField('level0Description', {
                  label: strings.Provision.Level0DescriptionFieldLabel,
                  description: strings.Provision.Level0DescriptionFieldDescription,
                  multiline: true,
                  placeholder: strings.Provision.DrawerLevel0DescriptionText,
                  rows: 4
                }),
                PropertyPaneTextField('level1Header', {
                  label: strings.Provision.Level1HeaderFieldLabel,
                  description: strings.Provision.Level1HeaderFieldDescription,
                  placeholder: strings.Provision.DrawerLevel1HeaderText
                }),
                PropertyPaneTextField('level1Description', {
                  label: strings.Provision.Level1DescriptionFieldLabel,
                  description: strings.Provision.Level1DescriptionFieldDescription,
                  multiline: true,
                  placeholder: strings.Provision.DrawerLevel1DescriptionText,
                  rows: 4
                }),
                PropertyPaneTextField('level2Header', {
                  label: strings.Provision.Level2HeaderFieldLabel,
                  description: strings.Provision.Level2HeaderFieldDescription,
                  placeholder: strings.Provision.DrawerLevel2HeaderText
                }),
                PropertyPaneTextField('level2Description', {
                  label: strings.Provision.Level2DescriptionFieldLabel,
                  description: strings.Provision.Level2DescriptionFieldDescription,
                  placeholder: strings.Provision.DrawerLevel2DescriptionText,
                  multiline: true,
                  rows: 4
                }),
                PropertyPaneTextField('footerDescription', {
                  label: strings.Provision.FooterDescriptionFieldLabel,
                  description: strings.Provision.FooterDescriptionFieldDescription,
                  placeholder: strings.Provision.DrawerFooterDescriptionText,
                  multiline: true,
                  rows: 4
                })
              ]
            },
            {
              groupName: strings.Provision.ShowHideGroupName,
              isCollapsed: true,
              groupFields: [
                PropertyPaneToggle('hideStatusMenu', {
                  label: strings.Provision.HideStatusMenuFieldLabel,
                  checked: propertiesWithDefaults.hideStatusMenu,
                  onText: strings.Provision.AutoOwnerOnText,
                  offText: strings.Provision.AutoOwnerOffText
                }),
                PropertyPaneToggle('hideSettingsMenu', {
                  label: strings.Provision.HideSettingsMenuFieldLabel,
                  checked: propertiesWithDefaults.hideSettingsMenu,
                  onText: strings.Provision.AutoOwnerOnText,
                  offText: strings.Provision.AutoOwnerOffText
                })
              ]
            },
            {
              groupName: strings.Provision.FieldLogicGroupName,
              isCollapsed: true,
              groupFields: [
                PropertyPaneDropdown('defaultExpirationDate', {
                  label: strings.Provision.DefaultExpirationDateFieldLabel,
                  options: [
                    { key: '0', text: strings.Provision.ExpirationDateNoneOption },
                    { key: '1', text: format(strings.Provision.ExpirationDateMonthOption, 1) },
                    { key: '3', text: format(strings.Provision.ExpirationDateMonthOption, 3) },
                    { key: '6', text: format(strings.Provision.ExpirationDateMonthOption, 6) },
                    { key: '12', text: format(strings.Provision.ExpirationDateMonthOption, 12) },
                    { key: '24', text: format(strings.Provision.ExpirationDateMonthOption, 24) }
                  ],
                  selectedKey: propertiesWithDefaults.defaultExpirationDate ?? '0',
                  disabled: propertiesWithDefaults.expirationDateMode !== 'monthDropdown'
                }),
                PropertyPaneToggle('readOnlyGroupLogic', {
                  label: strings.Provision.ReadOnlyGroupLogicFieldLabel,
                  checked: propertiesWithDefaults.readOnlyGroupLogic,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                }),
                PropertyPaneToggle('showTeamTemplateField', {
                  label: strings.Provision.ShowTeamTemplateFieldLabel,
                  checked: propertiesWithDefaults.showTeamTemplateField,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                })
              ]
            },
            {
              groupName: strings.Provision.AdvancedGroupName,
              isCollapsed: false,
              groupFields: [
                PropertyPaneTextField('provisionUrl', {
                  label: strings.Provision.ProvisionUrlFieldLabel,
                  description: strings.Provision.ProvisionUrlFieldDescription,
                  placeholder: this._instances[0]?.url || DEFAULT_PROVISION_URL
                }),
                PropertyPaneToggle('requireProvisionAccess', {
                  label: strings.Provision.RequireProvisionAccessFieldLabel,
                  checked: propertiesWithDefaults.requireProvisionAccess,
                  onText: strings.BooleanOn,
                  offText: strings.BooleanOff
                }),
                PropertyPaneTextField('provisionAccessGroupTitle', {
                  label: strings.Provision.ProvisionAccessGroupTitleFieldLabel,
                  description: strings.Provision.ProvisionAccessGroupTitleFieldDescription,
                  placeholder: DEFAULT_PROVISION_ACCESS_GROUP,
                  disabled: !propertiesWithDefaults.requireProvisionAccess
                }),
                PropertyPaneToggle('parentMode', {
                  label: strings.Provision.ParentModeFieldLabel,
                  checked: propertiesWithDefaults.parentMode ?? false,
                  onText: strings.Provision.AutoOwnerOnText,
                  offText: strings.Provision.AutoOwnerOffText
                }),
                PropertyPaneLabel('parentModeLabel', {
                  text: strings.Provision.ParentModeFieldDescription
                }),
                PropertyFieldCollectionData('fields', {
                  key: 'fieldsCollection',
                  label: strings.Provision.FieldsConfigurationLabel,
                  panelProps: {
                    type: 6
                  },
                  panelHeader: strings.Provision.FieldsConfigurationPanelHeader,
                  manageBtnLabel: strings.Provision.FieldsConfigurationManageBtnLabel,
                  value: fieldsValue,
                  disableItemCreation: true,
                  disableItemDeletion: true,
                  fields: [
                    {
                      id: 'order',
                      title: strings.Provision.FieldOrderLabel,
                      type: CustomCollectionFieldType.number,
                      disableEdit: true
                    },
                    {
                      id: 'fieldName',
                      title: strings.Provision.FieldNameLabel,
                      type: CustomCollectionFieldType.string,
                      required: true
                    },
                    {
                      id: 'displayName',
                      title: strings.Provision.FieldDisplayNameLabel,
                      type: CustomCollectionFieldType.string,
                      required: true
                    },
                    {
                      id: 'description',
                      title: strings.Provision.FieldDescriptionLabel,
                      type: CustomCollectionFieldType.string
                    },
                    {
                      id: 'placeholder',
                      title: strings.Provision.FieldPlaceholderLabel,
                      type: CustomCollectionFieldType.string
                    },
                    {
                      id: 'dataType',
                      title: strings.Provision.FieldDataTypeLabel,
                      type: CustomCollectionFieldType.dropdown,
                      disableEdit: true,
                      options: [
                        { key: 'text', text: strings.Provision.FieldDataTypeText },
                        { key: 'note', text: strings.Provision.FieldDataTypeNote },
                        { key: 'number', text: strings.Provision.FieldDataTypeNumber },
                        { key: 'choice', text: strings.Provision.FieldDataTypeChoice },
                        { key: 'userMulti', text: strings.Provision.FieldDataTypeUserMulti },
                        { key: 'guest', text: strings.Provision.FieldDataTypeGuest },
                        { key: 'date', text: strings.Provision.FieldDataTypeDate },
                        { key: 'tags', text: strings.Provision.FieldDataTypeTags },
                        { key: 'boolean', text: strings.Provision.FieldDataTypeBoolean },
                        { key: 'percentage', text: strings.Provision.FieldDataTypePercentage },
                        { key: 'site', text: strings.Provision.FieldDataTypeSite },
                        { key: 'image', text: strings.Provision.FieldDataTypeImage }
                      ],
                      defaultValue: 'text'
                    },
                    {
                      id: 'required',
                      title: strings.Provision.FieldRequiredLabel,
                      type: CustomCollectionFieldType.boolean,
                      defaultValue: false
                    },
                    {
                      id: 'hidden',
                      title: strings.Provision.FieldHiddenLabel,
                      type: CustomCollectionFieldType.boolean,
                      defaultValue: false
                    },
                    {
                      id: 'level',
                      title: strings.Provision.FieldLevelLabel,
                      type: CustomCollectionFieldType.number,
                      disableEdit: true,
                      defaultValue: 1
                    }
                  ]
                }),
                PropertyFieldMultiSelect('excludedTypes', {
                  key: 'excludedTypes',
                  label: strings.Provision.ExcludedTypesFieldLabel,
                  options: this._provisionTypes.map((type) => ({
                    key: type.key,
                    text: type.text
                  })),
                  selectedKeys: this.properties.excludedTypes ?? []
                }),
                PropertyPaneLabel('excludedTypesLabel', {
                  text: strings.Provision.ExcludedTypesFieldDescription
                }),
                PropertyFieldCollectionData('typeFieldConfigurations', {
                  key: 'typeFieldConfigurations',
                  label: strings.Provision.TypeConfigurationLabel,
                  panelProps: {
                    type: 6
                  },
                  panelHeader: strings.Provision.TypeConfigurationPanelHeader,
                  manageBtnLabel: strings.Provision.TypeConfigurationManageBtnLabel,
                  value: typeFieldConfigurationsValue,
                  fields: [
                    {
                      id: 'typeName',
                      title: strings.Provision.TypeNameLabel,
                      type: CustomCollectionFieldType.dropdown,
                      required: true,
                      options: this._provisionTypes
                    },
                    {
                      id: 'hiddenFields',
                      title: strings.Provision.HiddenFieldsForTypeLabel,
                      type: CustomCollectionFieldType.custom,

                      defaultValue: '',
                      onCustomRender: (field, value, onUpdate, item) => {
                        const availableFields = fieldsValue.map((f) => ({
                          key: f.fieldName,
                          text: f.displayName || f.fieldName
                        }))

                        let currentHiddenFields: string[] = []
                        if (value) {
                          if (typeof value === 'string') {
                            currentHiddenFields = value
                              .split(',')
                              .map((f) => f.trim())
                              .filter((f) => f)
                          } else if (Array.isArray(value)) {
                            currentHiddenFields = value
                          } else if (typeof value === 'object' && value !== null) {
                            if (value.toString() !== '[object Object]') {
                              currentHiddenFields = value
                                .toString()
                                .split(',')
                                .map((f) => f.trim())
                                .filter((f) => f)
                            }
                          }
                        }

                        const selectedFieldNames = currentHiddenFields
                          .map((fieldName) => {
                            const field = availableFields.find((f) => f.key === fieldName)
                            return field ? field.text : fieldName
                          })
                          .filter((name) => name)

                        const displayValue =
                          selectedFieldNames.length > 0
                            ? selectedFieldNames.join(', ')
                            : strings.Provision.HiddenFieldsForTypePlaceholder

                        return React.createElement(
                          IdPrefixProvider,
                          {
                            value: `hiddenFields-${field.id}-${item?.id || 'new'}`
                          },
                          React.createElement(
                            FluentProvider,
                            {
                              theme: customLightTheme,
                              style: { background: 'transparent' }
                            },
                            React.createElement(
                              Dropdown,
                              {
                                multiselect: true,
                                placeholder: strings.Provision.HiddenFieldsForTypePlaceholder,
                                value: displayValue,
                                selectedOptions: currentHiddenFields,
                                onOptionSelect: (event, data) => {
                                  const newSelectedOptions = data.selectedOptions || []
                                  onUpdate(field.id, newSelectedOptions.join(','))
                                }
                              },
                              availableFields.map((availableField) =>
                                React.createElement(
                                  Option,
                                  {
                                    key: availableField.key,
                                    value: availableField.key,
                                    text: availableField.text
                                  },
                                  availableField.text
                                )
                              )
                            )
                          )
                        )
                      }
                    },
                    {
                      id: 'requiredFields',
                      title: strings.Provision.RequiredFieldsForTypeLabel,
                      type: CustomCollectionFieldType.custom,

                      defaultValue: '',
                      onCustomRender: (field, value, onUpdate, item) => {
                        const availableFields = fieldsValue.map((f) => ({
                          key: f.fieldName,
                          text: f.displayName || f.fieldName
                        }))

                        let currentRequiredFields: string[] = []
                        if (value) {
                          if (typeof value === 'string') {
                            currentRequiredFields = value
                              .split(',')
                              .map((f) => f.trim())
                              .filter((f) => f)
                          } else if (Array.isArray(value)) {
                            currentRequiredFields = value
                          } else if (typeof value === 'object' && value !== null) {
                            if (value.toString() !== '[object Object]') {
                              currentRequiredFields = value
                                .toString()
                                .split(',')
                                .map((f) => f.trim())
                                .filter((f) => f)
                            }
                          }
                        }

                        const selectedFieldNames = currentRequiredFields
                          .map((fieldName) => {
                            const field = availableFields.find((f) => f.key === fieldName)
                            return field ? field.text : fieldName
                          })
                          .filter((name) => name)

                        const displayValue =
                          selectedFieldNames.length > 0
                            ? selectedFieldNames.join(', ')
                            : strings.Provision.RequiredFieldsForTypePlaceholder

                        return React.createElement(
                          IdPrefixProvider,
                          {
                            value: `requiredFields-${field.id}-${item?.id || 'new'}`
                          },
                          React.createElement(
                            FluentProvider,
                            {
                              theme: customLightTheme,
                              style: { background: 'transparent' }
                            },
                            React.createElement(
                              Dropdown,
                              {
                                multiselect: true,
                                placeholder: strings.Provision.RequiredFieldsForTypePlaceholder,
                                value: displayValue,
                                selectedOptions: currentRequiredFields,
                                onOptionSelect: (event, data) => {
                                  const newSelectedOptions = data.selectedOptions || []
                                  onUpdate(field.id, newSelectedOptions.join(','))
                                }
                              },
                              availableFields.map((availableField) =>
                                React.createElement(
                                  Option,
                                  {
                                    key: availableField.key,
                                    value: availableField.key,
                                    text: availableField.text
                                  },
                                  availableField.text
                                )
                              )
                            )
                          )
                        )
                      }
                    },
                    {
                      id: 'fieldConfigurations',
                      title: strings.Provision.FieldConfigurationJsonLabel,
                      type: CustomCollectionFieldType.custom,
                      defaultValue: '',
                      onCustomRender: (field, value, onUpdate) => {
                        let formattedValue = ''
                        if (value) {
                          if (typeof value === 'string') {
                            try {
                              const parsed = JSON.parse(value)
                              formattedValue = JSON.stringify(parsed, null, 2)
                            } catch {
                              formattedValue = value
                            }
                          } else if (typeof value === 'object' && value !== null) {
                            formattedValue = JSON.stringify(value, null, 2)
                          } else {
                            formattedValue = String(value)
                          }
                        }

                        return React.createElement('textarea', {
                          style: {
                            width: '100%',
                            minWidth: '680px',
                            minHeight: '120px',
                            fontFamily: 'monospace',
                            fontSize: '12px',
                            border: '1px solid #ccc',
                            borderRadius: '4px',
                            padding: '8px',
                            resize: 'vertical'
                          },
                          placeholder: strings.Provision.FieldConfigurationJsonPlaceholder,
                          defaultValue: formattedValue,
                          onBlur: (event: React.FocusEvent<HTMLTextAreaElement>) => {
                            onUpdate(field.id, event.target.value)
                          },
                          onChange: (() => {
                            let timeout: NodeJS.Timeout
                            return (event: React.ChangeEvent<HTMLTextAreaElement>) => {
                              clearTimeout(timeout)
                              timeout = setTimeout(() => {
                                onUpdate(field.id, event.target.value)
                              }, 500)
                            }
                          })()
                        })
                      }
                    }
                  ]
                }),
                PropertyPaneLabel('propertyEditorLabel', {
                  text: strings.Provision.PropertyEditorLabel
                }),
                PropertyPanePropertyEditor({
                  key: 'propertyEditor',
                  webpart: this
                }),
                PropertyFieldMessage('propertyEditorDescription', {
                  key: 'propertyEditorDescription',
                  messageType: 0,
                  text: strings.Provision.PropertyEditorDescription,
                  isVisible: true
                }),
                PropertyPaneToggle('debugMode', {
                  label: strings.Provision.DebugModeLabel,
                  onText: strings.Provision.DebugModeOnText,
                  offText: strings.Provision.DebugModeOffText
                })
              ]
            }
          ]
        }
      ]
    }
  }

  protected async onPropertyPaneFieldChanged(
    propertyPath: string,
    oldValue: any,
    newValue: any
  ): Promise<void> {
    if (propertyPath === 'provisionUrl' && oldValue !== newValue) {
      // An emptied field falls back to the tenant registry default
      this._resolvedProvisionUrl = resolveProvisionUrl(newValue, this._instances, false)
      await this.loadProvisionTypes()
      this.context.propertyPane.refresh()
      void this.render()
    }
    if (propertyPath === 'expirationDateMode' && oldValue !== newValue) {
      // Refresh property pane to enable/disable defaultExpirationDate dropdown
      this.context.propertyPane.refresh()
    }
    super.onPropertyPaneFieldChanged(propertyPath, oldValue, newValue)
  }
}
