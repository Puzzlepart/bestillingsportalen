# CustomerSpecific runbook - customer extension point for the Bestillingsportalen solution.
#
# Invoked by the ProcessProvisionRequest Logic App right after ConfigureSpace has
# finished configuring a newly provisioned space, with the same parameter set
# (except spaceImage). Use it for customer-specific post-provisioning steps -
# extra lists, permissions, integrations with external systems, etc. It runs as
# the Automation account's system-assigned managed identity, just like
# ConfigureSpace (Connect-PnPOnline -Url $siteUrl -ManagedIdentity).
#
# IMPORTANT: This runbook is created ONCE by deploy.ps1 (with this default no-op
# content) and is NEVER overwritten by later deploys/upgrades - unlike the other
# runbooks, which are kept in sync with the repo. The content here is owned by
# the customer/consultant: edit it directly in the Azure Portal or maintain it
# in a customer-specific repo.
[CmdletBinding()]
Param
(
    [Parameter (Mandatory = $false)]
    [string] $groupId,
    [string] $siteUrl,
    [string] $spaceType,
    [string] $spaceTypeInternal,
    [string] $externalSharing,
    [string] $owners,
    [string] $members,
    [string] $visitors,
    [string] $visibility,
    [string] $classification,
    [string] $joinHub,
    [string] $hubSiteId,
    [string] $timeZoneId,
    [string] $lcid,
    [bool] $enableAllowAccessRequests,
    [string] $defaultExternalSharingSetting,
    [int] $storageQuota,
    [int] $storageQuotaWarning,
    [bool] $syncHubPermissions,
    [bool] $disableDocSync,
    [string] $retentionLabel,
    [string] $sensitivityLabel,
    [string] $sensitivityLabelLibrary,
    [string] $featuresToActivate,
    [string] $applyPnPTemplate,
    [string] $pnpTemplateUrl,
    [string] $themeName,
    [string] $siteTemplateTitle,
    [string] $siteCollectionAdmins,
    [string] $siteDesignId,
    [bool] $internalChannel,
    [bool] $readOnlyGroup,
    [string] $defaultReadOnlyGroup,
    $metadata,
    [string] $parentSiteUrl
)

Write-Output "CustomerSpecific runbook invoked for $siteUrl ($spaceTypeInternal) - no customer-specific steps configured."
