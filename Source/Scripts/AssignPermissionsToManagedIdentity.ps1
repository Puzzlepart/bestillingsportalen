<#
.SYNOPSIS
    Assigns the solution's Microsoft Graph / SharePoint app roles to the managed
    identities. Runnable STANDALONE by a Global Administrator - this is the file to
    hand over when the person running deploy.ps1 does not have the Entra rights to
    assign app roles (deploy.ps1 -SkipAppRoles prints the exact command to run).

.DESCRIPTION
    Two modes:

    HANDOVER (canonical role sets baked into this file):
        ./AssignPermissionsToManagedIdentity.ps1 -TenantId <tenantId> `
            -AutomationIdentityId <objectId> -UamiId <objectId>

        Assigns the solution's documented role sets to the automation account's
        system-assigned identity and the logic apps' user-assigned identity. Either
        parameter can be given alone. deploy.ps1 -SkipAppRoles prints this command
        with the object ids filled in - no other files are needed.

    REPAIR (explicit scopes, one identity):
        ./AssignPermissionsToManagedIdentity.ps1 -ManagedIdentityId <objectId> `
            -Scopes @("Group.ReadWrite.All") -IncludeSharePointSitesFullControl

    Requirements: PowerShell 7+, the Microsoft.Graph PowerShell module
    (Install-Module Microsoft.Graph.Applications), and an account that can assign
    app roles - Global Administrator, or Privileged Role Administrator + Cloud
    Application Administrator. Sign-in is interactive.

    The role sets mirror what deploy.ps1 assigns (AssignManagedIdentityPermissions /
    AssignUamiPermissions) - keep them in sync if the solution's permissions change.
    They are documented call-by-call in Data-access-security.md.

.PARAMETER AutomationIdentityId
    Object (principal) id of the automation account's SYSTEM-ASSIGNED managed
    identity. Gets: Graph Group.ReadWrite.All + User.Read.All, SharePoint
    Sites.FullControl.All.

.PARAMETER UamiId
    Object (principal) id of the USER-ASSIGNED managed identity used by the logic
    apps. Gets: 9 Graph roles + SharePoint Sites.FullControl.All.

.PARAMETER TenantId
    Tenant to sign in to. Recommended in the handover scenario so the sign-in
    cannot land in the wrong tenant.

.PARAMETER ManagedIdentityId
    Repair mode: object id of a single managed identity to assign -Scopes to.

.PARAMETER Scopes
    Repair mode: Microsoft Graph app roles to assign.

.PARAMETER IncludeSharePointSitesFullControl
    Repair mode: also assign SharePoint Sites.FullControl.All.
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$AutomationIdentityId,
    [Parameter(Mandatory = $false)]
    [string]$UamiId,
    [Parameter(Mandatory = $false)]
    [string]$TenantId,
    [Parameter(Mandatory = $false)]
    [string]$ManagedIdentityId,
    [Parameter(Mandatory = $false)]
    [string[]]$Scopes = @("Group.ReadWrite.All", "User.Read.All"),
    [Parameter(Mandatory = $false)]
    [switch]$IncludeSharePointSitesFullControl
)

if (-not $AutomationIdentityId -and -not $UamiId -and -not $ManagedIdentityId) {
    Write-Host "Nothing to do: provide -AutomationIdentityId and/or -UamiId (handover mode), or -ManagedIdentityId (repair mode). See Get-Help ./AssignPermissionsToManagedIdentity.ps1 -Full." -ForegroundColor Red
    exit 1
}

# The canonical role sets. MUST mirror deploy.ps1 (AssignManagedIdentityPermissions /
# AssignUamiPermissions) - that script is the source of truth at install time, this
# one exists so the assignment can be done by someone else, later.
$automationGraphRoles = @("Group.ReadWrite.All", "User.Read.All")
$uamiGraphRoles = @(
    "Directory.Read.All",
    "GroupSettings.ReadWrite.All",
    "Group.ReadWrite.All",
    "InformationProtectionPolicy.Read.All",
    "Sites.Read.All",
    "TeamTemplates.Read.All",
    "Community.ReadWrite.All",
    "User.Invite.All",
    "User.ReadWrite.All"
)

try {
    # Application.Read.All to resolve the service principals, AppRoleAssignment for
    # the grants themselves. Nothing else - earlier versions over-asked
    # (RoleManagement/Application.ReadWrite/DelegatedPermissionGrant), which made the
    # consent prompt look far more dramatic than the operation is.
    $connectParams = @{ Scopes = @("AppRoleAssignment.ReadWrite.All", "Application.Read.All") }
    if ($TenantId) { $connectParams.TenantId = $TenantId }
    Connect-MgGraph @connectParams
}
catch {
    Write-Host "Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
    exit 1
}

try {
    $GraphServicePrincipal = Get-MgServicePrincipal -Filter "AppId eq '00000003-0000-0000-c000-000000000000'"
    $SpoServicePrincipal = Get-MgServicePrincipal -Filter "AppId eq '00000003-0000-0ff1-ce00-000000000000'"
}
catch {
    Write-Host "Failed to resolve the Microsoft Graph / SharePoint service principals: $_" -ForegroundColor Red
    exit 1
}

$script:assignmentFailed = $false

# Assigns one app role to one principal, skipping roles that are already assigned.
# $ExistingAssignments must be the principal's current assignments (fetched once per
# principal by the caller).
function Add-AppRoleToPrincipal {
    param ($PrincipalId, $ResourceServicePrincipal, $PermissionScope, $ExistingAssignments)

    $appRole = $ResourceServicePrincipal.AppRoles | Where-Object Value -eq $PermissionScope | Where-Object AllowedMemberTypes -contains "Application"
    if ($null -eq $appRole) {
        Write-Host "  App role '$PermissionScope' not found on $($ResourceServicePrincipal.DisplayName)" -ForegroundColor Red
        $script:assignmentFailed = $true
        return
    }

    if ($ExistingAssignments | Where-Object AppRoleId -eq $appRole.Id) {
        Write-Host "  '$PermissionScope' already assigned on $($ResourceServicePrincipal.DisplayName). Skipping." -ForegroundColor Gray
        return
    }

    $bodyParam = @{
        PrincipalId = $PrincipalId
        ResourceId  = $ResourceServicePrincipal.Id
        AppRoleId   = $appRole.Id
    }
    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $PrincipalId -BodyParameter $bodyParam | Out-Null
    Write-Host "  Assigned '$PermissionScope' ($($ResourceServicePrincipal.DisplayName))" -ForegroundColor Green
}

# Assigns a Graph role set (+ optionally SharePoint Sites.FullControl.All) to one
# managed identity, with per-identity lookup of existing assignments.
function Grant-RoleSet {
    param (
        [string]$PrincipalId,
        [string]$Label,
        [string[]]$GraphRoles,
        [bool]$IncludeSpoFullControl
    )

    Write-Host "$($Label) ($PrincipalId):" -ForegroundColor Yellow
    try {
        $principal = Get-MgServicePrincipal -ServicePrincipalId $PrincipalId
        Write-Host "  Found: $($principal.DisplayName)" -ForegroundColor Gray
    }
    catch {
        Write-Host "  Managed identity '$PrincipalId' was not found: $_" -ForegroundColor Red
        $script:assignmentFailed = $true
        return
    }

    $existing = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $PrincipalId -All

    foreach ($scope in $GraphRoles) {
        try {
            Add-AppRoleToPrincipal -PrincipalId $PrincipalId -ResourceServicePrincipal $GraphServicePrincipal -PermissionScope $scope -ExistingAssignments $existing
        }
        catch {
            Write-Host "  Failed to assign '$scope': $_" -ForegroundColor Red
            $script:assignmentFailed = $true
        }
    }

    if ($IncludeSpoFullControl) {
        if ($null -eq $SpoServicePrincipal) {
            Write-Host "  SharePoint Online service principal not found in the tenant" -ForegroundColor Red
            $script:assignmentFailed = $true
        }
        else {
            try {
                Add-AppRoleToPrincipal -PrincipalId $PrincipalId -ResourceServicePrincipal $SpoServicePrincipal -PermissionScope "Sites.FullControl.All" -ExistingAssignments $existing
            }
            catch {
                Write-Host "  Failed to assign SharePoint 'Sites.FullControl.All': $_" -ForegroundColor Red
                $script:assignmentFailed = $true
            }
        }
    }
}

if ($AutomationIdentityId) {
    Grant-RoleSet -PrincipalId $AutomationIdentityId -Label "Automation account system-assigned identity" -GraphRoles $automationGraphRoles -IncludeSpoFullControl $true
}
if ($UamiId) {
    Grant-RoleSet -PrincipalId $UamiId -Label "Logic apps user-assigned identity" -GraphRoles $uamiGraphRoles -IncludeSpoFullControl $true
}
if ($ManagedIdentityId) {
    Grant-RoleSet -PrincipalId $ManagedIdentityId -Label "Managed identity (repair mode)" -GraphRoles $Scopes -IncludeSpoFullControl $IncludeSharePointSitesFullControl.IsPresent
}

if ($script:assignmentFailed) {
    Write-Host ""
    Write-Host "One or more assignments failed - review the output above and re-run. Already-assigned roles are skipped, so re-running is safe." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "All requested app roles are in place. New app roles can take a few minutes to propagate, and managed identity tokens are cached for up to ~24 hours - if the logic apps still get 401/403, wait before troubleshooting further." -ForegroundColor Green
