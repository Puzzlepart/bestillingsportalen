param(
  [Parameter(Mandatory = $true)]
  $ManagedIdentityId = "xxx" # Object (principal) ID of system assigned managed identity
)

# This script requires the Microsoft Graph PowerShell module to be installed.
# It assigns the necessary permissions to a system assigned managed identity to access Microsoft Graph and SharePoint Online.

$GraphPermissionScopes = @(
  "Group.ReadWrite.All"
)

try {
  Connect-MgGraph -Scopes "Application.ReadWrite.All", "DelegatedPermissionGrant.ReadWrite.All"
}
catch {
  Write-Host "Failed to connect to Microsoft Graph: $_"
  exit 1
}

try {
  $ManagedIdentity = Get-MgServicePrincipal -ServicePrincipalId $ManagedIdentityId
  if ($null -eq $ManagedIdentity) {
    Write-Host "System assigned managed identity not found"
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

foreach ($PermissionScope in $GraphPermissionScopes) {
  try {
    $appRole = $GraphServicePrincipal.AppRoles | Where-Object Value -eq $PermissionScope | Where-Object AllowedMemberTypes -contains "Application"
    if ($null -eq $appRole) {
      Write-Host "App role for scope '$PermissionScope' not found"
      continue
    }

    $bodyParam = @{
      PrincipalId = $ManagedIdentityId
      ResourceId  = $GraphServicePrincipal.Id
      AppRoleId   = $appRole.Id
    }
    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ManagedIdentityId -BodyParameter $bodyParam
    Write-Host "Assigned '$PermissionScope' to managed identity"
  }
  catch {
    Write-Host "Failed to assign '$PermissionScope' to managed identity: $_"
  }
}
