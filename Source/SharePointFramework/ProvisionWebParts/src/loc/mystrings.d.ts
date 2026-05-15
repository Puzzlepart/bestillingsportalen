declare interface IProvisionWebPartsStrings {
  PropertyPaneDescription: string;
  BasicGroupName: string;
  TitleFieldLabel: string;
  DescriptionFieldLabel: string;
  WebPartTitleInfoLabelTitle: string;
  DisplayModeFieldLabel: string;
  DisplayModeInlineLabel: string;
  DisplayModeDialogLabel: string;
  ViewStatusButton: string;
  StatusDialogTitle: string;
  StatusSummaryTotal: string;
  StatusSummaryPending: string;
  StatusSummaryFailed: string;
  CloseButton: string;
  GuestRequestListTitleFieldLabel: string;
  GuestRequestListTitleFieldDescription: string;
  GuestRequestSiteUrlFieldLabel: string;
  GuestRequestSiteUrlFieldDescription: string;

  InviteButton: string;
  InviteDrawerHeader: string;
  InviteDrawerDescription: string;
  GuestPickerLabel: string;
  GuestPickerPlaceholder: string;
  GuestPickerInvalidEmail: string;
  CancelButton: string;
  SendInvitationsButton: string;
  RefreshButton: string;
  RetryButton: string;

  StatusHeader: string;
  StatusEmpty: string;
  StatusSearchPlaceholder: string;

  ColumnEmail: string;
  ColumnStatus: string;
  ColumnRequestedBy: string;
  ColumnCreated: string;
  ColumnError: string;

  StatusPending: string;
  StatusInvited: string;
  StatusFailed: string;

  ToastSuccessTitle: string;
  ToastSuccessBody: string;
  ToastErrorTitle: string;
  ToastErrorBody: string;
}

declare module 'ProvisionWebPartsStrings' {
  const strings: IProvisionWebPartsStrings;
  export = strings;
}
