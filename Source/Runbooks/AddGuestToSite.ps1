<#
.SYNOPSIS
    Adds an invited guest to a SharePoint site after the tenant invitation has succeeded.

.DESCRIPTION
    Called by the ProcessGuestRequest Logic App once an external user has been invited
    to the tenant via the Microsoft Graph invitations endpoint. Handles two orthogonal
    actions per invite:

    1. Optional Microsoft 365 group membership (when the target site is group-connected
       and `M365GroupRole = 'Guest'`).
    2. Optional SharePoint user group membership:
       - 'AddToExisting' adds the guest to a named SharePoint group on the site.
       - 'CreateNew' creates a new SharePoint group, binds the given permission level,
         and adds the guest to it.
       - 'None' skips the SharePoint group step entirely.

    Authenticates via the Azure Automation account's system-assigned managed identity.
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

Write-Output "AddGuestToSite started for $guestEmail on $siteUrl"
Write-Output "Settings: m365GroupRole=$m365GroupRole, spGroupAction=$spGroupAction, spGroupName='$spGroupName', spPermissionLevel='$spPermissionLevel'"

try {
    Connect-PnPOnline -Url $siteUrl -ManagedIdentity
    Write-Output 'Connected to SharePoint Online'

    if ($m365GroupRole -eq 'Guest') {
        $web = Get-PnPWeb -Includes 'GroupId'
        $groupId = $web.GroupId
        if ($groupId -and $groupId -ne [Guid]::Empty) {
            Write-Output "Adding $guestEmail as guest member of M365 group $groupId"
            Add-PnPMicrosoft365GroupMember -Identity $groupId -Users $guestEmail
            Write-Output 'Added to M365 group'
        }
        else {
            Write-Output 'Site is not connected to a Microsoft 365 group; skipping M365GroupRole step'
        }
    }

    switch ($spGroupAction) {
        'AddToExisting' {
            if ([string]::IsNullOrWhiteSpace($spGroupName)) {
                throw 'spGroupName is required when spGroupAction = AddToExisting'
            }
            Write-Output "Adding $guestEmail to existing SharePoint group '$spGroupName'"
            Add-PnPUserToGroup -LoginName $guestEmail -Identity $spGroupName
            Write-Output 'Added to existing SP group'
        }
        'CreateNew' {
            if ([string]::IsNullOrWhiteSpace($spGroupName)) {
                throw 'spGroupName is required when spGroupAction = CreateNew'
            }
            if ([string]::IsNullOrWhiteSpace($spPermissionLevel)) {
                throw 'spPermissionLevel is required when spGroupAction = CreateNew'
            }
            $existing = Get-PnPGroup -Identity $spGroupName -ErrorAction SilentlyContinue
            if ($existing) {
                Write-Output "SharePoint group '$spGroupName' already exists; reusing"
            }
            else {
                Write-Output "Creating new SharePoint group '$spGroupName' with permission '$spPermissionLevel'"
                $newGroup = New-PnPGroup -Title $spGroupName
                Set-PnPGroupPermissions -Identity $newGroup.Title -AddRole $spPermissionLevel
            }
            Add-PnPUserToGroup -LoginName $guestEmail -Identity $spGroupName
            Write-Output "Added $guestEmail to '$spGroupName'"
        }
        'None' {
            Write-Output 'No SharePoint group action requested'
        }
        default {
            throw "Unknown spGroupAction '$spGroupAction'"
        }
    }

    Write-Output 'AddGuestToSite completed successfully'
}
catch {
    Write-Error "AddGuestToSite failed: $($_.Exception.Message)"
    throw
}
