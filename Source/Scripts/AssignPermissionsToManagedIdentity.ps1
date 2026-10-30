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
    Application Administrator. Sign-in is interactive. The PowerShell version and the
    modules are checked before anything else, with the command that fixes them.

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

.PARAMETER Force
    Skip the confirmation prompt. The signed-in account, tenant and target
    identities are still printed, and a sign-in to a tenant other than -TenantId
    still stops the script.
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
    [switch]$IncludeSharePointSitesFullControl,
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

if (-not $AutomationIdentityId -and -not $UamiId -and -not $ManagedIdentityId) {
    Write-Host "Nothing to do: provide -AutomationIdentityId and/or -UamiId (handover mode), or -ManagedIdentityId (repair mode). See Get-Help ./AssignPermissionsToManagedIdentity.ps1 -Full." -ForegroundColor Red
    exit 1
}

# The ids are copied by hand from a handover message, and a line break in an e-mail or a
# terminal cuts them short. At a customer a UAMI id one character short went all the way
# through: Graph refused every call with 'Invalid object identifier', and the run still
# ended with 'All requested app roles are in place'. Checked before the sign-in, so a
# bad id costs nothing.
$AutomationIdentityId = "$AutomationIdentityId".Trim()
$UamiId = "$UamiId".Trim()
$TenantId = "$TenantId".Trim()
$ManagedIdentityId = "$ManagedIdentityId".Trim()
$invalidIds = @()
foreach ($idParam in @(
        @{ Name = 'AutomationIdentityId'; Value = $AutomationIdentityId },
        @{ Name = 'UamiId'; Value = $UamiId },
        @{ Name = 'TenantId'; Value = $TenantId },
        @{ Name = 'ManagedIdentityId'; Value = $ManagedIdentityId })) {
    if ($idParam.Value -and $idParam.Value -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
        $invalidIds += "  -$($idParam.Name) '$($idParam.Value)' has $($idParam.Value.Length) characters - a GUID has 36 (8-4-4-4-12 hexadecimal digits)"
    }
}
if ($invalidIds.Count -gt 0) {
    Write-Host "Not a valid id - nothing has been signed in to or assigned:" -ForegroundColor Red
    $invalidIds | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host "The id was probably cut off or broken across lines when it was copied. Copy it again from the handover command and re-run." -ForegroundColor Yellow
    exit 1
}

# The prerequisites, checked up front. This script is handed to a Global Administrator
# who has usually not run anything from the solution before - without the checks a
# missing module surfaced as "Failed to connect to Microsoft Graph: The term
# 'Connect-MgGraph' is not recognized", and with only Microsoft.Graph.Authentication
# installed the sign-in went through and the run failed at the first lookup.
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "This script requires PowerShell 7 or newer (current: $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)). Install it from https://aka.ms/powershell and run the script in pwsh, not Windows PowerShell." -ForegroundColor Red
    exit 1
}
$installCommand = "Install-Module Microsoft.Graph.Applications -Scope CurrentUser"
$missingModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Applications' | Where-Object {
        -not (Get-Module -Name $_) -and -not (Get-Module -Name $_ -ListAvailable)
    })
if ($missingModules.Count -gt 0) {
    Write-Host "Missing PowerShell module(s): $($missingModules -join ', '). Install with: $installCommand (Microsoft.Graph.Authentication comes with it), then re-run." -ForegroundColor Red
    exit 1
}
# Importing proves the pair loads together: Microsoft.Graph.Applications pins its exact
# Microsoft.Graph.Authentication version, and a mismatch fails here instead of mid-run
try {
    Import-Module Microsoft.Graph.Applications -ErrorAction Stop
}
catch {
    Write-Host "Microsoft.Graph.Applications could not be loaded: $(($_.Exception.Message -split "`r?`n")[0])" -ForegroundColor Red
    Write-Host "Usually mismatched Microsoft.Graph module versions. Bring them to the same version with: Update-Module Microsoft.Graph.Authentication, Microsoft.Graph.Applications - or $installCommand -Force - then re-run in a NEW PowerShell session." -ForegroundColor Yellow
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

$targets = @()
if ($AutomationIdentityId) {
    $targets += [pscustomobject]@{ Id = $AutomationIdentityId; Label = "Automation account system-assigned identity"; GraphRoles = $automationGraphRoles; IncludeSpo = $true }
}
if ($UamiId) {
    $targets += [pscustomobject]@{ Id = $UamiId; Label = "Logic apps user-assigned identity"; GraphRoles = $uamiGraphRoles; IncludeSpo = $true }
}
if ($ManagedIdentityId) {
    $targets += [pscustomobject]@{ Id = $ManagedIdentityId; Label = "Managed identity (repair mode)"; GraphRoles = $Scopes; IncludeSpo = $IncludeSharePointSitesFullControl.IsPresent }
}

function Connect-Graph {
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
}

# Connect-MgGraph silently reuses a cached session - in practice the admin's run went
# straight through as whichever account was signed in last, with nothing on screen
# saying who that was. Show the account, the tenant and what is about to change, and
# ask before writing anything. 's' signs out and back in, for when the cached account
# is the wrong one.
function Confirm-Session {
    while ($true) {
        $context = Get-MgContext
        $tenantName = $null
        try {
            # Best effort: reading the organization needs User.Read, which the session
            # normally has but this script does not ask for
            $tenantName = (Invoke-MgGraphRequest -Method GET -Uri 'v1.0/organization?$select=displayName' -ErrorAction Stop).value[0].displayName
        }
        catch {}
        $tenantMismatch = $TenantId -and ($context.TenantId -ne $TenantId)

        Write-Host ""
        Write-Host "Microsoft Graph session" -ForegroundColor Cyan
        Write-Host "  Signed in as : $($context.Account)"
        Write-Host "  Tenant       : $(if ($tenantName) { "$tenantName " })($($context.TenantId))" -ForegroundColor $(if ($tenantMismatch) { 'Red' } else { 'Gray' })
        Write-Host ""
        Write-Host "App roles to assign" -ForegroundColor Cyan
        $notFound = @()
        foreach ($target in $targets) {
            $name = try { (Get-MgServicePrincipal -ServicePrincipalId $target.Id -ErrorAction Stop).DisplayName } catch { $null }
            $roles = "$(@($target.GraphRoles).Count) Graph role(s)$(if ($target.IncludeSpo) { ' + SharePoint Sites.FullControl.All' })"
            if ($name) {
                Write-Host "  $($target.Label): $name ($($target.Id)) - $roles"
            }
            else {
                Write-Host "  $($target.Label): NOT FOUND in this tenant ($($target.Id)) - $roles" -ForegroundColor Red
                $notFound += $target
            }
        }
        Write-Host ""

        # Not offered as 'y': every assignment to an identity that cannot be read fails,
        # and continuing used to look like it had worked. Signing in again is offered
        # because a wrong tenant or account is one way to get here.
        if ($tenantMismatch -or $notFound.Count -gt 0) {
            if ($tenantMismatch) {
                Write-Host "The session is signed in to tenant $($context.TenantId), not $TenantId." -ForegroundColor Red
            }
            if ($notFound.Count -gt 0) {
                Write-Host "$(@($notFound.Label) -join ' and ') could not be found in tenant $($context.TenantId) - nothing will be assigned." -ForegroundColor Red
                Write-Host "Check the object id against the handover command (look it up with: az identity show --resource-group <rg> --name <uami> --query principalId for the user-assigned identity, or on the automation account's Identity page), or sign in to the right tenant." -ForegroundColor Yellow
            }
            if ($Force) { exit 1 }
            $answer = Read-Host "s = sign in as a different account, n = cancel"
        }
        elseif ($Force) {
            return
        }
        else {
            $answer = Read-Host "Continue? (y = yes, s = sign in as a different account, n = cancel)"
            if ($answer -eq 'y') { return }
        }

        if ($answer -eq 's') {
            Disconnect-MgGraph | Out-Null
            Connect-Graph
            continue
        }
        Write-Host "Cancelled - nothing has been assigned." -ForegroundColor Yellow
        exit 0
    }
}

Connect-Graph
Confirm-Session

try {
    $GraphServicePrincipal = Get-MgServicePrincipal -Filter "AppId eq '00000003-0000-0000-c000-000000000000'" -ErrorAction Stop
    $SpoServicePrincipal = Get-MgServicePrincipal -Filter "AppId eq '00000003-0000-0ff1-ce00-000000000000'" -ErrorAction Stop
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
    # -ErrorAction Stop on every Graph call: the Microsoft.Graph cmdlets report failures
    # as NON-terminating errors, so without it the callers' catch blocks never ran, and
    # a refused assignment printed 'Assigned' and counted as a success.
    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $PrincipalId -BodyParameter $bodyParam -ErrorAction Stop | Out-Null
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
        $principal = Get-MgServicePrincipal -ServicePrincipalId $PrincipalId -ErrorAction Stop
        Write-Host "  Found: $($principal.DisplayName)" -ForegroundColor Gray
    }
    catch {
        Write-Host "  Managed identity '$PrincipalId' was not found: $_" -ForegroundColor Red
        $script:assignmentFailed = $true
        return
    }

    try {
        $existing = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $PrincipalId -All -ErrorAction Stop
    }
    catch {
        Write-Host "  Could not read the existing app role assignments of '$PrincipalId': $_" -ForegroundColor Red
        $script:assignmentFailed = $true
        return
    }

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

foreach ($target in $targets) {
    Grant-RoleSet -PrincipalId $target.Id -Label $target.Label -GraphRoles $target.GraphRoles -IncludeSpoFullControl $target.IncludeSpo
}

if ($script:assignmentFailed) {
    Write-Host ""
    Write-Host "One or more assignments failed - review the output above and re-run. Already-assigned roles are skipped, so re-running is safe." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "All requested app roles are in place. New app roles can take a few minutes to propagate, and managed identity tokens are cached for up to ~24 hours - if the logic apps still get 401/403, wait before troubleshooting further." -ForegroundColor Green
