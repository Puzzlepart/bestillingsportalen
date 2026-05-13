define([], function () {
  return {
    PropertyPaneDescription: 'Settings for the Invite Guests web part.',
    BasicGroupName: 'General',
    TitleFieldLabel: 'Title',
    GuestRequestListTitleFieldLabel: 'Guest request list title',
    GuestRequestListTitleFieldDescription: 'The SharePoint list where invitation requests are stored. Default: Guest Requests',
    GuestRequestSiteUrlFieldLabel: 'Bestillingsportalen site URL',
    GuestRequestSiteUrlFieldDescription: 'URL of the site where the Guest Requests list lives (typically Bestillingsportalen). Leave blank to use the current site.',

    InviteButton: 'Invite guests',
    InviteDrawerHeader: 'Invite guests to this site',
    InviteDrawerDescription: 'Enter one or more email addresses. Each guest receives an invitation and shows up in the list below once processed.',
    GuestPickerLabel: 'Email addresses',
    GuestPickerPlaceholder: 'Type an email address and press Enter',
    GuestPickerInvalidEmail: 'Invalid email address',
    CancelButton: 'Cancel',
    SendInvitationsButton: 'Send invitations',
    RefreshButton: 'Refresh',
    RetryButton: 'Retry',

    StatusHeader: 'Invitation status',
    StatusEmpty: 'No invitations recorded for this site yet.',
    StatusSearchPlaceholder: 'Search by email …',

    ColumnEmail: 'Email',
    ColumnStatus: 'Status',
    ColumnRequestedBy: 'Requested by',
    ColumnCreated: 'Sent',
    ColumnError: 'Error',

    StatusPending: 'Pending',
    StatusInvited: 'Invited',
    StatusFailed: 'Failed',

    ToastSuccessTitle: 'Invitations sent',
    ToastSuccessBody: 'The requests have been recorded and are being processed in the background.',
    ToastErrorTitle: 'Could not send invitations',
    ToastErrorBody: 'An error occurred. Check the console for details.'
  };
});
