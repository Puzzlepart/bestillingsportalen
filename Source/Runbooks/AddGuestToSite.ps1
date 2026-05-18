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

    NB: A freshly invited B2B guest does not yet exist in the target site's user info
    list, so `Add-PnPGroupMember -LoginName <email>` may fail. We call CSOM
    `Web.EnsureUser()` first (no PnP cmdlet wraps it) to materialize the guest as a
    SharePoint principal, then pass the returned claims-encoded LoginName to the
    group cmdlets.

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

Write-Output "AddGuestToSite started for '$guestEmail' on '$siteUrl'"
Write-Output "Settings: m365GroupRole='$m365GroupRole', spGroupAction='$spGroupAction', spGroupName='$spGroupName', spPermissionLevel='$spPermissionLevel'"

if ([string]::IsNullOrWhiteSpace($siteUrl)) {
    throw "siteUrl parameter is empty. Verify the Logic App passes 'SiteUrl' from the list item."
}
if ([string]::IsNullOrWhiteSpace($guestEmail)) {
    throw "guestEmail parameter is empty. Verify the Logic App passes 'Title' from the list item."
}

try {
    Connect-PnPOnline -Url $siteUrl -ManagedIdentity
    Write-Output 'Connected to SharePoint Online'

    # Materialize the guest as a SharePoint principal on this site so the group cmdlets
    # can resolve them. PnP.PowerShell does not expose an EnsureUser cmdlet, so we drop
    # to the underlying CSOM context. After Invoke-PnPQuery the user info entry exists
    # and $ensuredUser.LoginName is the claims-encoded UPN we pass downstream.
    $pnpContext = Get-PnPContext
    $ensuredUser = $pnpContext.Web.EnsureUser($guestEmail)
    $pnpContext.Load($ensuredUser)
    Invoke-PnPQuery
    if (-not $ensuredUser -or [string]::IsNullOrWhiteSpace($ensuredUser.LoginName)) {
        throw "EnsureUser returned no LoginName for '$guestEmail' — the guest cannot be resolved on this site."
    }
    $guestLoginName = $ensuredUser.LoginName
    Write-Output "Ensured guest on site. LoginName='$guestLoginName'"

    if ($m365GroupRole -eq 'Guest') {
        $web = Get-PnPWeb -Includes 'GroupId'
        $groupId = $web.GroupId
        if ($groupId -and $groupId -ne [Guid]::Empty) {
            Write-Output "Adding '$guestEmail' as guest member of M365 group $groupId"
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
            Write-Output "Resolving existing SharePoint group '$spGroupName'"
            $group = Get-PnPGroup -Identity $spGroupName
            Write-Output "Adding '$guestLoginName' to '$($group.Title)'"
            Add-PnPGroupMember -LoginName $guestLoginName -Identity $group
            Write-Output 'Added to existing SP group'
        }
        'CreateNew' {
            if ([string]::IsNullOrWhiteSpace($spGroupName)) {
                throw 'spGroupName is required when spGroupAction = CreateNew'
            }
            if ([string]::IsNullOrWhiteSpace($spPermissionLevel)) {
                throw 'spPermissionLevel is required when spGroupAction = CreateNew'
            }
            $group = Get-PnPGroup -Identity $spGroupName -ErrorAction SilentlyContinue
            if ($group) {
                Write-Output "SharePoint group '$spGroupName' already exists; reusing"
            }
            else {
                Write-Output "Creating new SharePoint group '$spGroupName' with permission '$spPermissionLevel'"
                $group = New-PnPGroup -Title $spGroupName
                Set-PnPGroupPermissions -Identity $group.Title -AddRole $spPermissionLevel
            }
            Write-Output "Adding '$guestLoginName' to '$($group.Title)'"
            Add-PnPGroupMember -LoginName $guestLoginName -Identity $group
            Write-Output "Added to '$spGroupName'"
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
