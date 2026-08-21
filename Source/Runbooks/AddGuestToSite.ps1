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

# Guests get access through the standard Microsoft 365 guest model: membership
# in the M365 group ('Member', shown as "Gjest" in the web part), which grants
# the team, site and group resources (Teams/Planner/OneNote). Guests can never
# OWN a group, so 'Owner' is rejected as defense in depth even if a list item
# says otherwise. 'Visitor' is honored for items created before the role lock
# (read access via the associated Visitors group).
Write-Output "[STEP 1/2] Applying site role '$m365GroupRole'..."
switch ($m365GroupRole) {
    'None' {
        Write-Output '[STEP 1/2] Skipped — no site role requested'
    }
    'Member' {
        if ($isGroupConnected) {
            Add-PnPMicrosoft365GroupMember -Identity $site.GroupId -Users $guestEmail
            Write-Output "[STEP 1/2] Added '$guestEmail' as guest member of M365 group $($site.GroupId)"
        }
        else {
            $group = Get-PnPGroup -AssociatedMemberGroup
            Add-PnPGroupMember -LoginName $guestLoginName -Identity $group
            Write-Output "[STEP 1/2] Added '$guestLoginName' as Member to '$($group.Title)'"
        }
    }
    'Visitor' {
        $group = Get-PnPGroup -AssociatedVisitorGroup
        Add-PnPGroupMember -LoginName $guestLoginName -Identity $group
        Write-Output "[STEP 1/2] Added '$guestLoginName' as Visitor to '$($group.Title)'"
    }
    'Owner' {
        throw "m365GroupRole 'Owner' is not allowed — external guests cannot own a Microsoft 365 group. Use 'Member' (guest membership) or a SharePoint group (spGroupAction) instead."
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
        # The web part stores English level names ('Edit' etc.), but role
        # definition NAMES are localized per site language (a Norwegian site has
        # 'Redigering', and 'Edit' does not exist). Resolve via the language-
        # independent RoleTypeKind and pass the site's actual role name.
        $roleTypeByLevel = @{
            'Read'         = 'Reader'
            'Contribute'   = 'Contributor'
            'Edit'         = 'Editor'
            'Full Control' = 'Administrator'
        }
        $roleDef = $null
        $roleTypeKind = $roleTypeByLevel[$spPermissionLevel]
        if ($roleTypeKind) {
            $roleDef = Get-PnPRoleDefinition | Where-Object { "$($_.RoleTypeKind)" -eq $roleTypeKind } | Select-Object -First 1
        }
        if (-not $roleDef) {
            # Custom levels have no RoleTypeKind — fall back to a literal name match.
            $roleDef = Get-PnPRoleDefinition | Where-Object { $_.Name -eq $spPermissionLevel } | Select-Object -First 1
        }
        if (-not $roleDef) {
            throw "No role definition found for permission level '$spPermissionLevel' on this site (checked RoleTypeKind '$roleTypeKind' and literal name)"
        }
        $group = Get-PnPGroup -Identity $spGroupName -ErrorAction SilentlyContinue
        if (-not $group) {
            $group = New-PnPGroup -Title $spGroupName
            Set-PnPGroupPermissions -Identity $group.Title -AddRole $roleDef.Name
            Write-Output "[STEP 2/2] Created group '$($group.Title)' with permission '$($roleDef.Name)' (requested '$spPermissionLevel')"
        }
        Add-PnPGroupMember -LoginName $guestLoginName -Identity $group
        Write-Output "[STEP 2/2] Added '$guestLoginName' to '$($group.Title)'"
    }
    default {
        throw "Unknown spGroupAction '$spGroupAction'"
    }
}

Write-Output '[DONE] AddGuestToSite completed successfully'
