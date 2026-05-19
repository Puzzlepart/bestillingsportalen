declare interface IProvisionWebPartsStrings {
  PropertyPaneDescription: string
  BasicGroupName: string
  TitleFieldLabel: string
  DescriptionFieldLabel: string
  WebPartTitleInfoLabelTitle: string
  DisplayModeFieldLabel: string
  DisplayModeInlineLabel: string
  DisplayModeDialogLabel: string
  InviteModeFieldLabel: string
  InviteModeSingleLabel: string
  InviteModeMultiLabel: string
  InviteAccessLevelFieldLabel: string
  InviteAccessLevelOwnerLabel: string
  InviteAccessLevelMemberLabel: string
  InviteAccessLevelAnyoneLabel: string
  PerGuestProfileModeFieldLabel: string
  PerGuestRoleModeFieldLabel: string
  FeatureModeDisabledLabel: string
  FeatureModeOptionalLabel: string
  FeatureModeEnforcedLabel: string
  PerGuestProfileLabel: string
  PerGuestRoleLabel: string
  ViewStatusButton: string
  StatusDialogTitle: string
  StatusSummaryTotal: string
  StatusSummaryPending: string
  StatusSummaryFailed: string
  CloseButton: string
  GuestRequestListTitleFieldLabel: string
  GuestRequestListTitleFieldDescription: string
  GuestRequestSiteUrlFieldLabel: string
  GuestRequestSiteUrlFieldDescription: string

  InviteButton: string
  InviteDrawerHeader: string
  InviteDrawerDescription: string
  GuestPickerLabel: string
  GuestPickerPlaceholder: string
  GuestPickerInvalidEmail: string
  GuestPickerNoOptionsText: string
  GuestPickerHelperText: string
  FirstNameLabel: string
  FirstNameDescription: string
  LastNameLabel: string
  LastNameDescription: string
  CompanyLabel: string
  CompanyDescription: string
  GuestExistsBadge: string
  GuestExistsMissingDetails: string
  NoValuePlaceholder: string
  AccessInfoBanner: string
  CancelButton: string
  SendInvitationsButton: string
  RefreshButton: string
  RetryButton: string

  StatusHeader: string
  StatusEmpty: string
  StatusSearchPlaceholder: string

  ColumnEmail: string
  ColumnStatus: string
  ColumnRequestedBy: string
  ColumnCreated: string
  ColumnError: string
  CopyRedeemUrlLabel: string
  CopyRedeemUrlCopied: string

  StatusPending: string
  StatusInvited: string
  StatusFailed: string

  ToastSuccessTitle: string
  ToastSuccessBody: string
  ToastErrorTitle: string
  ToastErrorBody: string

  M365GroupSectionTitle: string
  M365GroupRoleNoneLabel: string
  M365GroupRoleVisitorLabel: string
  M365GroupRoleMemberLabel: string
  M365GroupRoleOwnerLabel: string
  M365GroupRoleSectionDescription: string

  SPGroupSectionTitle: string
  SPGroupActionNoneLabel: string
  SPGroupActionExistingLabel: string
  SPGroupActionNewLabel: string
  SPGroupExistingPickerLabel: string
  SPGroupExistingPickerPlaceholder: string
  SPGroupNewNameLabel: string
  SPGroupNewNamePlaceholder: string
  SPGroupNewPermissionLabel: string
  SPGroupNewNameRequired: string

  SPPermissionRead: string
  SPPermissionContribute: string
  SPPermissionEdit: string
  SPPermissionFullControl: string

  ColumnM365GroupRole: string
  ColumnSPGroupAction: string
  ColumnSPGroupName: string
  ColumnSPPermissionLevel: string
}

declare module 'ProvisionWebPartsStrings' {
  const strings: IProvisionWebPartsStrings
  export = strings
}
