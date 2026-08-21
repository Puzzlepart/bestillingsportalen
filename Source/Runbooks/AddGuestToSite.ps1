<#
.SYNOPSIS
    Adds an invited guest to a SharePoint site after the tenant invitation has succeeded.
    Called by the ProcessGuestRequest Logic App. Authenticates via system-assigned
    managed identity.
#>
[CmdletBinding()]
Param
(
    [Parameter(Mandatory = $true)][string] $siteUrl,
    [Parameter(Mandatory = $true)][string] $guestEmail,
    [Parameter(Mandatory = $false)][string] $m365GroupRole = 'None',
    [Parameter(Mandatory = $false)][string] $spGroupAction = 'None',
    [Parameter(Mandatory = $false)][string] $spGroupName = '',
    [Parameter(Mandatory = $false)][string] $spPermissionLevel = ''
)

$ErrorActionPreference = 'Stop'

Write-Output "[INIT] AddGuestToSite started: guestEmail='$guestEmail' siteUrl='$siteUrl' m365GroupRole='$m365GroupRole' spGroupAction='$spGroupAction' spGroupName='$spGroupName' spPermissionLevel='$spPermissionLevel'"

if ([string]::IsNullOrWhiteSpace($siteUrl)) { throw 'siteUrl parameter is empty' }
if ([string]::IsNullOrWhiteSpace($guestEmail)) { throw 'guestEmail parameter is empty' }

Connect-PnPOnline -Url $siteUrl -ManagedIdentity
Write-Output '[INIT] Connected to SharePoint Online'

# CSOM EnsureUser — no PnP cmdlet wraps it. Materializes the guest on this site.
$pnpContext = Get-PnPContext
$ensuredUser = $pnpContext.Web.EnsureUser($guestEmail)
$pnpContext.Load($ensuredUser)
Invoke-PnPQuery
$guestLoginName = $ensuredUser.LoginName
Write-Output "[INIT] Ensured guest on site. LoginName='$guestLoginName'"

$site = Get-PnPSite -Includes GroupId
$isGroupConnected = $site.GroupId -ne [Guid]::Empty
Write-Output "[INIT] Site context: isGroupConnected=$isGroupConnected, GroupId='$($site.GroupId)'"

# The flow only ever invites EXTERNAL users (ProcessGuests posts to Graph
# /invitations), and a guest can never be Member/Owner of the site: Entra does
# not allow guests as M365 group owners, and Member would cascade Teams/Planner/
# mailbox access onto an external user. The requestable role is therefore locked
# to Visitor (read access via the associated Visitors group) or None — anything
# else is rejected here as defense in depth, even if a list item says otherwise.
Write-Output "[STEP 1/2] Applying site role '$m365GroupRole'..."
switch ($m365GroupRole) {
    'None' {
        Write-Output '[STEP 1/2] Skipped — no site role requested'
    }
    'Visitor' {
        $group = Get-PnPGroup -AssociatedVisitorGroup
        Add-PnPGroupMember -LoginName $guestLoginName -Identity $group
        Write-Output "[STEP 1/2] Added '$guestLoginName' as Visitor to '$($group.Title)'"
    }
    { $_ -in 'Member', 'Owner' } {
        throw "m365GroupRole '$m365GroupRole' is not allowed for external guests — only 'Visitor' or 'None'. Grant additional access via a SharePoint group (spGroupAction) instead."
    }
    default {
        throw "Unknown m365GroupRole '$m365GroupRole'"
    }
}

Write-Output "[STEP 2/2] Applying SP group action '$spGroupAction'..."
switch ($spGroupAction) {
    'None' {
        Write-Output '[STEP 2/2] Skipped — no SP group action requested'
    }
    'AddToExisting' {
        if ([string]::IsNullOrWhiteSpace($spGroupName)) {
            throw 'spGroupName is required when spGroupAction = AddToExisting'
        }
        $group = Get-PnPGroup -Identity $spGroupName
        Add-PnPGroupMember -LoginName $guestLoginName -Identity $group
        Write-Output "[STEP 2/2] Added '$guestLoginName' to '$($group.Title)'"
    }
    'CreateNew' {
        if ([string]::IsNullOrWhiteSpace($spGroupName)) {
            throw 'spGroupName is required when spGroupAction = CreateNew'
        }
        if ([string]::IsNullOrWhiteSpace($spPermissionLevel)) {
            throw 'spPermissionLevel is required when spGroupAction = CreateNew'
        }
        $group = Get-PnPGroup -Identity $spGroupName -ErrorAction SilentlyContinue
        if (-not $group) {
            $group = New-PnPGroup -Title $spGroupName
            Set-PnPGroupPermissions -Identity $group.Title -AddRole $spPermissionLevel
            Write-Output "[STEP 2/2] Created group '$($group.Title)' with permission '$spPermissionLevel'"
        }
        Add-PnPGroupMember -LoginName $guestLoginName -Identity $group
        Write-Output "[STEP 2/2] Added '$guestLoginName' to '$($group.Title)'"
    }
    default {
        throw "Unknown spGroupAction '$spGroupAction'"
    }
}

Write-Output '[DONE] AddGuestToSite completed successfully'
