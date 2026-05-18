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

Write-Output "AddGuestToSite started: guestEmail='$guestEmail' siteUrl='$siteUrl' m365GroupRole='$m365GroupRole' spGroupAction='$spGroupAction' spGroupName='$spGroupName' spPermissionLevel='$spPermissionLevel'"

if ([string]::IsNullOrWhiteSpace($siteUrl)) { throw 'siteUrl parameter is empty' }
if ([string]::IsNullOrWhiteSpace($guestEmail)) { throw 'guestEmail parameter is empty' }

Connect-PnPOnline -Url $siteUrl -ManagedIdentity

# CSOM EnsureUser — no PnP cmdlet wraps it. Materializes the guest on this site.
$pnpContext = Get-PnPContext
$ensuredUser = $pnpContext.Web.EnsureUser($guestEmail)
$pnpContext.Load($ensuredUser)
Invoke-PnPQuery
$guestLoginName = $ensuredUser.LoginName
Write-Output "Ensured guest on site. LoginName='$guestLoginName'"

$site = Get-PnPSite -Includes GroupId
$isGroupConnected = $site.GroupId -ne [Guid]::Empty

# Hybrid: on M365-group-connected sites the SP Owner/Member groups are auto-managed
# (synced from the M365 group), so we use Graph cmdlets. Visitors is always SP-only.
# On non-group sites all three roles map to SP associated groups.
switch ($m365GroupRole) {
    'None' {
        Write-Output 'No site role assignment requested'
    }
    'Visitor' {
        $group = Get-PnPGroup -AssociatedVisitorGroup
        Add-PnPGroupMember -LoginName $guestLoginName -Identity $group
        Write-Output "Added '$guestLoginName' as Visitor to '$($group.Title)'"
    }
    'Member' {
        if ($isGroupConnected) {
            Add-PnPMicrosoft365GroupMember -Identity $site.GroupId -Users $guestEmail
            Write-Output "Added '$guestEmail' as Member to M365 group $($site.GroupId)"
        }
        else {
            $group = Get-PnPGroup -AssociatedMemberGroup
            Add-PnPGroupMember -LoginName $guestLoginName -Identity $group
            Write-Output "Added '$guestLoginName' as Member to '$($group.Title)'"
        }
    }
    'Owner' {
        if ($isGroupConnected) {
            Add-PnPMicrosoft365GroupOwner -Identity $site.GroupId -Users $guestEmail
            Write-Output "Added '$guestEmail' as Owner to M365 group $($site.GroupId)"
        }
        else {
            $group = Get-PnPGroup -AssociatedOwnerGroup
            Add-PnPGroupMember -LoginName $guestLoginName -Identity $group
            Write-Output "Added '$guestLoginName' as Owner to '$($group.Title)'"
        }
    }
    default {
        throw "Unknown m365GroupRole '$m365GroupRole'"
    }
}

switch ($spGroupAction) {
    'None' {
        Write-Output 'No SP group action requested'
    }
    'AddToExisting' {
        if ([string]::IsNullOrWhiteSpace($spGroupName)) {
            throw 'spGroupName is required when spGroupAction = AddToExisting'
        }
        $group = Get-PnPGroup -Identity $spGroupName
        Add-PnPGroupMember -LoginName $guestLoginName -Identity $group
        Write-Output "Added '$guestLoginName' to '$($group.Title)'"
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
            Write-Output "Created group '$($group.Title)' with permission '$spPermissionLevel'"
        }
        Add-PnPGroupMember -LoginName $guestLoginName -Identity $group
        Write-Output "Added '$guestLoginName' to '$($group.Title)'"
    }
    default {
        throw "Unknown spGroupAction '$spGroupAction'"
    }
}

Write-Output 'AddGuestToSite completed successfully'
