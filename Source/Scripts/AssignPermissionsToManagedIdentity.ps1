param(
  [Parameter(Mandatory = $true)]
  [string]$ManagedIdentityId, # Object (principal) ID of the managed identity (system or user-assigned)
  [Parameter(Mandatory = $false)]
  [string[]]$Scopes = @("Group.ReadWrite.All", "User.Read.All"), # Microsoft Graph app roles to assign
  [Parameter(Mandatory = $false)]
  [switch]$IncludeSharePointSitesFullControl # Also assign SharePoint Sites.FullControl.All
)

# This script requires the Microsoft Graph PowerShell module to be installed.
# It assigns the necessary permissions to a managed identity to access Microsoft Graph
# and (optionally) SharePoint Online.
#
# The scope sets below mirror what deploy.ps1 assigns (AssignManagedIdentityPermissions /
# AssignUamiPermissions) - keep them in sync if the solution's permissions change.
#
# Examples:
#   Automation account system-assigned identity (default scope set):
#     ./AssignPermissionsToManagedIdentity.ps1 -ManagedIdentityId <objectId> -IncludeSharePointSitesFullControl
#   Logic apps user-assigned identity (repair/manual setup - normally handled by deploy.ps1):
#     ./AssignPermissionsToManagedIdentity.ps1 -ManagedIdentityId <objectId> -IncludeSharePointSitesFullControl -Scopes @(
#       "Directory.Read.All", "GroupSettings.ReadWrite.All", "Group.ReadWrite.All",
#       "InformationProtectionPolicy.Read.All", "Sites.Read.All", "TeamsTemplates.Read.All",
#       "Community.ReadWrite.All", "User.Invite.All", "User.ReadWrite.All")

try {
  Connect-MgGraph -Scopes "Directory.Read.All", "AppRoleAssignment.ReadWrite.All", "RoleManagement.ReadWrite.Directory", "Application.ReadWrite.All", "DelegatedPermissionGrant.ReadWrite.All"
}
catch {
  Write-Host "Failed to connect to Microsoft Graph: $_"
  exit 1
}

try {
  $ManagedIdentity = Get-MgServicePrincipal -ServicePrincipalId $ManagedIdentityId
  if ($null -eq $ManagedIdentity) {
    Write-Host "Managed identity not found"
    exit 1
  }
}
catch {
  Write-Host "Failed to get managed identity: $_"
  exit 1
}

try {
  $GraphServicePrincipal = Get-MgServicePrincipal -Filter "AppId eq '00000003-0000-0000-c000-000000000000'"
}
catch {
  Write-Host "Failed to get Microsoft Graph service principal: $_"
  exit 1
}

$existingAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ManagedIdentityId -All

function Add-AppRoleToManagedIdentity {
  param ($ResourceServicePrincipal, $PermissionScope)

  $appRole = $ResourceServicePrincipal.AppRoles | Where-Object Value -eq $PermissionScope | Where-Object AllowedMemberTypes -contains "Application"
  if ($null -eq $appRole) {
    Write-Host "App role for scope '$PermissionScope' not found on $($ResourceServicePrincipal.DisplayName)"
    $script:assignmentFailed = $true
    return
  }

  if ($existingAssignments | Where-Object AppRoleId -eq $appRole.Id) {
    Write-Host "'$PermissionScope' already assigned on $($ResourceServicePrincipal.DisplayName). Skipping."
    return
  }

  $bodyParam = @{
    PrincipalId = $ManagedIdentityId
    ResourceId  = $ResourceServicePrincipal.Id
    AppRoleId   = $appRole.Id
  }
  New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ManagedIdentityId -BodyParameter $bodyParam
  Write-Host "Assigned '$PermissionScope' ($($ResourceServicePrincipal.DisplayName)) to managed identity"
}

$script:assignmentFailed = $false

foreach ($PermissionScope in $Scopes) {
  try {
    Add-AppRoleToManagedIdentity -ResourceServicePrincipal $GraphServicePrincipal -PermissionScope $PermissionScope
  }
  catch {
    Write-Host "Failed to assign '$PermissionScope' to managed identity: $_"
    $script:assignmentFailed = $true
  }
}

if ($IncludeSharePointSitesFullControl) {
  try {
    $SpoServicePrincipal = Get-MgServicePrincipal -Filter "AppId eq '00000003-0000-0ff1-ce00-000000000000'"
    if ($null -eq $SpoServicePrincipal) {
      Write-Host "SharePoint Online service principal not found in the tenant"
      $script:assignmentFailed = $true
    }
    else {
      Add-AppRoleToManagedIdentity -ResourceServicePrincipal $SpoServicePrincipal -PermissionScope "Sites.FullControl.All"
    }
  }
  catch {
    Write-Host "Failed to assign SharePoint 'Sites.FullControl.All' to managed identity: $_"
    $script:assignmentFailed = $true
  }
}

if ($script:assignmentFailed) {
  Write-Host "One or more assignments failed - review the output above and re-run." -ForegroundColor Red
  exit 1
}
