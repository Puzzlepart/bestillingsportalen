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
    [Parameter(Mandatory = $false)][string] $spPermissionLevel = '',
    [Parameter(Mandatory = $false)][string] $guestEntraGroup = ''
)

$ErrorActionPreference = 'Stop'

Write-Output "[INIT] AddGuestToSite started: guestEmail='$guestEmail' siteUrl='$siteUrl' m365GroupRole='$m365GroupRole' spGroupAction='$spGroupAction' spGroupName='$spGroupName' spPermissionLevel='$spPermissionLevel' guestEntraGroup='$guestEntraGroup'"

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

# Graph addresses users by object id or UPN — and a guest's UPN is
# 'name_domain#EXT#@tenant', never their e-mail address, so passing the e-mail
# 404s for every guest. The ensured user's claims login name ends with the real
# UPN; resolve the object id from that. Cached — both the M365 group step and
# the Entra guest group step need it.
$script:guestObjectId = $null
function Resolve-GuestObjectId {
    if (-not $script:guestObjectId) {
        $guestUpn = $guestLoginName.Split('|')[-1]
        $encodedUpn = [System.Uri]::EscapeDataString($guestUpn)
        $aadUser = Invoke-PnPGraphMethod -Url "v1.0/users/$($encodedUpn)?`$select=id"
        $script:guestObjectId = $aadUser.id
    }
    return $script:guestObjectId
}

# Guests get access through the standard Microsoft 365 guest model: membership
# in the M365 group ('Member', shown as "Gjest" in the web part), which grants
# the team, site and group resources (Teams/Planner/OneNote). Guests can never
# OWN a group, so 'Owner' is rejected as defense in depth even if a list item
# says otherwise. 'Visitor' is honored for items created before the role lock
# (read access via the associated Visitors group).
Write-Output "[STEP 1/3] Applying site role '$m365GroupRole'..."
switch ($m365GroupRole) {
    'None' {
        Write-Output '[STEP 1/3] Skipped — no site role requested'
    }
    'Member' {
        if ($isGroupConnected) {
            $guestId = Resolve-GuestObjectId
            try {
                Add-PnPMicrosoft365GroupMember -Identity $site.GroupId -Users $guestId
                Write-Output "[STEP 1/3] Added guest '$guestId' as member of M365 group $($site.GroupId)"
            }
            catch {
                # Re-inviting an existing member returns Graph 400
                # 'One or more added object references already exist' — that is
                # the desired end state, not a failure.
                if ("$_" -match 'already exist') {
                    Write-Output "[STEP 1/3] Guest '$guestId' is already a member of M365 group $($site.GroupId) — skipped"
                }
                else {
                    throw
                }
            }
        }
        else {
            $group = Get-PnPGroup -AssociatedMemberGroup
            Add-PnPGroupMember -LoginName $guestLoginName -Identity $group
            Write-Output "[STEP 1/3] Added '$guestLoginName' as Member to '$($group.Title)'"
        }
    }
    'Visitor' {
        $group = Get-PnPGroup -AssociatedVisitorGroup
        Add-PnPGroupMember -LoginName $guestLoginName -Identity $group
        Write-Output "[STEP 1/3] Added '$guestLoginName' as Visitor to '$($group.Title)'"
    }
    'Owner' {
        throw "m365GroupRole 'Owner' is not allowed — external guests cannot own a Microsoft 365 group. Use 'Member' (guest membership) or a SharePoint group (spGroupAction) instead."
    }
    default {
        throw "Unknown m365GroupRole '$m365GroupRole'"
    }
}

Write-Output "[STEP 2/3] Applying SP group action '$spGroupAction'..."
switch ($spGroupAction) {
    'None' {
        Write-Output '[STEP 2/3] Skipped — no SP group action requested'
    }
    'AddToExisting' {
        if ([string]::IsNullOrWhiteSpace($spGroupName)) {
            throw 'spGroupName is required when spGroupAction = AddToExisting'
        }
        $group = Get-PnPGroup -Identity $spGroupName
        Add-PnPGroupMember -LoginName $guestLoginName -Identity $group
        Write-Output "[STEP 2/3] Added '$guestLoginName' to '$($group.Title)'"
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
            Write-Output "[STEP 2/3] Created group '$($group.Title)' with permission '$($roleDef.Name)' (requested '$spPermissionLevel')"
        }
        Add-PnPGroupMember -LoginName $guestLoginName -Identity $group
        Write-Output "[STEP 2/3] Added '$guestLoginName' to '$($group.Title)'"
    }
    default {
        throw "Unknown spGroupAction '$spGroupAction'"
    }
}

# Optional, tenant-wide: every invited guest is also added to a designated Entra ID
# group (deploy parameter 'guestEntraGroup' — object id or display name). Lets the
# organisation grant all guests shared baseline access in one place, e.g. read
# access to the hub site and the app catalog. Works for security groups and M365
# groups (Group.ReadWrite.All); role-assignable and on-premises-synced groups are
# not writable through Graph and will fail here.
Write-Output "[STEP 3/3] Applying Entra guest group membership..."
if ([string]::IsNullOrWhiteSpace($guestEntraGroup)) {
    Write-Output '[STEP 3/3] Skipped — no Entra guest group configured'
}
else {
    if ($guestEntraGroup -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
        $entraGroupId = $guestEntraGroup
    }
    else {
        # Display names are not unique in Entra ID, so a name must resolve to
        # exactly one group — anything else is a configuration error we surface
        # rather than guessing.
        $escapedName = $guestEntraGroup.Replace("'", "''")
        $encodedFilter = [System.Uri]::EscapeDataString("displayName eq '$escapedName'")
        $groupResult = Invoke-PnPGraphMethod -Url "v1.0/groups?`$filter=$encodedFilter&`$select=id,displayName"
        $candidates = @($groupResult.value)
        if ($candidates.Count -eq 0) {
            throw "No Entra ID group found with display name '$guestEntraGroup' (guestEntraGroup). Create the group, or configure the parameter with the group's object id."
        }
        if ($candidates.Count -gt 1) {
            throw "Multiple Entra ID groups ($($candidates.Count)) share the display name '$guestEntraGroup' (guestEntraGroup). Configure the parameter with the intended group's object id instead."
        }
        $entraGroupId = $candidates[0].id
    }
    $guestId = Resolve-GuestObjectId
    try {
        Invoke-PnPGraphMethod -Url "v1.0/groups/$entraGroupId/members/`$ref" -Method Post -Content @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$guestId" }
        Write-Output "[STEP 3/3] Added guest '$guestId' to Entra group '$guestEntraGroup' ($entraGroupId)"
    }
    catch {
        # Same idempotency contract as step 1: an existing member is the desired
        # end state, not a failure.
        if ("$_" -match 'already exist') {
            Write-Output "[STEP 3/3] Guest '$guestId' is already a member of Entra group '$guestEntraGroup' ($entraGroupId) — skipped"
        }
        else {
            throw
        }
    }
}

Write-Output '[DONE] AddGuestToSite completed successfully'
