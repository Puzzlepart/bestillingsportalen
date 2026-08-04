<#
.SYNOPSIS
    Generates a ready-to-use parameters.json for deploy.ps1 by reading the environment
    you are signed in to with the Azure CLI.

.DESCRIPTION
    Connects with the Azure CLI (runs 'az login' if needed), lets you pick a subscription
    if you have several, and auto-fills everything that can be derived from the connected
    environment:

        tenantId        - from the Azure CLI context
        subscriptionId  - from the Azure CLI context (interactive picker when multiple)
        fullTenantName  - the tenant's initial *.onmicrosoft.com domain (via Microsoft Graph)
        spoTenantName   - derived from the initial domain prefix

    Everything else gets a sensible default from parameters.template.json. The service
    account UPN is prompted for (or passed with -ServiceAccountUPN).

    The script only reads from Azure - it changes nothing in the environment.

.PARAMETER Tenant
    The target (customer) tenant to generate parameters for - initial domain
    (e.g. contoso.onmicrosoft.com) or tenant id. Prompted for when omitted.
    The script signs the Azure CLI in to THIS tenant and only offers
    subscriptions that belong to it, so consultants working across customer
    tenants cannot generate parameters against the wrong environment.

.PARAMETER OutputPath
    Where to write the generated file. Default: .\parameters.json (next to deploy.ps1).

.PARAMETER ServiceAccountUPN
    UPN of the service account used for the delegated API connections. Prompted for when omitted.

.PARAMETER Region
    Azure region for the resources. Default: norwayeast.

.PARAMETER EnableSensitivity
    Enable the sensitivity label functionality (requires a service account without MFA).

.PARAMETER Force
    Overwrite an existing parameters.json without asking.

.EXAMPLE
    ./GenerateParameters.ps1

.EXAMPLE
    ./GenerateParameters.ps1 -Tenant contoso.onmicrosoft.com -ServiceAccountUPN svc-bp@contoso.com -Region westeurope -Force
#>
param
(
    [string]$Tenant,
    [string]$OutputPath = ".\parameters.json",
    [string]$ServiceAccountUPN,
    [string]$Region = "norwayeast",
    [switch]$EnableSensitivity,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "Azure CLI is not installed. Install it from https://learn.microsoft.com/cli/azure/install-azure-cli and re-run." -ForegroundColor Red
    exit 1
}

$templatePath = Join-Path $PSScriptRoot "parameters.template.json"
if (-not (Test-Path $templatePath)) {
    Write-Host "parameters.template.json was not found next to this script ($templatePath)." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# 1. Target tenant + Azure CLI sign-in
# Always anchored to an explicitly stated target tenant, so consultants who
# work across customer tenants cannot generate parameters against the wrong
# environment by accident. Only subscriptions in the target tenant are offered.
# ---------------------------------------------------------------------------
while ([string]::IsNullOrWhiteSpace($Tenant)) {
    $Tenant = Read-Host "Which tenant (customer) are you generating parameters for? Enter the initial domain or tenant id (e.g. contoso.onmicrosoft.com)"
}

# A UPN pasted by mistake (user@tenant.onmicrosoft.com) - the domain part is the tenant
if ($Tenant -match '@') {
    $derivedTenant = ($Tenant -split '@')[-1]
    Write-Host "'$Tenant' looks like a user account (UPN), not a tenant - using the domain part '$derivedTenant' as the tenant." -ForegroundColor Yellow
    $Tenant = $derivedTenant
}

# Resolve the tenant to its id via the public OpenID discovery endpoint (no auth
# needed). This catches typos with a clear error BEFORE any sign-in, and gives an
# exact tenant id to verify the session against afterwards.
if ($Tenant -match '^[0-9a-fA-F\-]{36}$') {
    $targetTenantId = $Tenant
}
else {
    try {
        $oidc = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$Tenant/v2.0/.well-known/openid-configuration" -ErrorAction Stop
        $targetTenantId = ($oidc.issuer -split '/')[3]
        Write-Host "Tenant '$Tenant' resolved to tenant id $targetTenantId" -ForegroundColor Green
    }
    catch {
        Write-Host "Could not resolve tenant '$Tenant' - check the spelling (expected an initial domain like contoso.onmicrosoft.com, or a tenant id). Aborting." -ForegroundColor Red
        exit 1
    }
}

# The Azure CLI caches sessions across runs (and tenants), so an existing session
# with access to the target tenant can be reused without a new MFA round trip -
# it is offered for reuse instead of forcing a fresh az login every time.
Write-Host "Checking for an existing Azure CLI session for tenant '$Tenant' ($targetTenantId)..." -ForegroundColor Yellow

$cachedSubsJson = az account list --output json 2>$null
$cachedSubs = if ($cachedSubsJson) { @($cachedSubsJson | ConvertFrom-Json) } else { @() }
$cachedForTarget = @($cachedSubs | Where-Object { $_.tenantId -eq $targetTenantId })

$account = $null
if ($cachedForTarget.Count -gt 0) {
    Write-Host "Found an existing Azure CLI session with access to tenant '$Tenant' as $($cachedForTarget[0].user.name)." -ForegroundColor Green
    $reuse = if ($Force) { 'y' } else { Read-Host "Reuse this session? ( y = reuse / n = sign in again )" }
    if ($reuse -eq 'y') {
        az account set --subscription $cachedForTarget[0].id
        $account = az account show | ConvertFrom-Json
    }
}

if ($null -eq $account) {
    Write-Host "Signing in to tenant '$Tenant' - a browser window will open; pick the account you will run the installation with..." -ForegroundColor Yellow
    az login --tenant $targetTenantId --only-show-errors | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "az login against tenant '$Tenant' ($targetTenantId) failed - see the error above. Aborting." -ForegroundColor Red
        exit 1
    }
    $account = az account show | ConvertFrom-Json
}

# The generated parameters must come from the TARGET tenant - never silently
# continue on whatever tenant a leftover session happens to be in.
if ($null -eq $account -or $account.tenantId -ne $targetTenantId) {
    Write-Host "The active Azure CLI session is in tenant '$($account.tenantId)', not the target '$targetTenantId'. Aborting." -ForegroundColor Red
    exit 1
}

Write-Host "Signed in as $($account.user.name) in tenant $($account.tenantId)" -ForegroundColor Green

# Only offer subscriptions that belong to the target tenant
$subscriptions = @(az account list --query "[?state=='Enabled' && tenantId=='$($account.tenantId)']" --output json | ConvertFrom-Json)
if ($subscriptions.Count -eq 0) {
    Write-Host "No enabled subscriptions found in tenant $($account.tenantId) for $($account.user.name)." -ForegroundColor Red
    exit 1
}
if ($subscriptions.Count -gt 1) {
    Write-Host ""
    Write-Host "Subscriptions available in this tenant (signed in as $($account.user.name)):" -ForegroundColor Yellow
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        $tenantLabel = if ($subscriptions[$i].tenantDefaultDomain) { $subscriptions[$i].tenantDefaultDomain } else { $subscriptions[$i].tenantId }
        $marker = if ($subscriptions[$i].id -eq $account.id) { " (current)" } else { "" }
        Write-Host ("  [{0}] {1} - {2} (tenant {3}){4}" -f $i, $subscriptions[$i].name, $subscriptions[$i].id, $tenantLabel, $marker)
    }
    $choice = Read-Host "Select the subscription to deploy to (0-$($subscriptions.Count - 1), enter for current)"
    if (-not [string]::IsNullOrWhiteSpace($choice)) {
        $selected = $subscriptions[[int]$choice]
        az account set --subscription $selected.id
        $account = az account show | ConvertFrom-Json
    }
}
elseif ($subscriptions[0].id -ne $account.id) {
    az account set --subscription $subscriptions[0].id
    $account = az account show | ConvertFrom-Json
}

Write-Host "Using subscription '$($account.name)' ($($account.id)) in tenant $($account.tenantId) as $($account.user.name)" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 2. Tenant names via Microsoft Graph (initial *.onmicrosoft.com domain)
# ---------------------------------------------------------------------------
Write-Host "Resolving tenant domain names via Microsoft Graph..." -ForegroundColor Yellow
$fullTenantName = $null
$spoTenantName = $null
try {
    $org = az rest --method get --url "https://graph.microsoft.com/v1.0/organization?`$select=displayName,verifiedDomains" 2>$null | ConvertFrom-Json
    $initialDomain = $org.value[0].verifiedDomains | Where-Object { $_.isInitial } | Select-Object -First 1
    if ($null -ne $initialDomain) {
        $fullTenantName = $initialDomain.name
        $spoTenantName = $fullTenantName -replace '\.onmicrosoft\.com$', ''
        Write-Host "Tenant: $($org.value[0].displayName) - initial domain $fullTenantName (SPO tenant name: $spoTenantName)" -ForegroundColor Green
    }
}
catch {}
if ([string]::IsNullOrEmpty($fullTenantName)) {
    Write-Host "Could not resolve the tenant's initial domain via Graph (insufficient permissions?)." -ForegroundColor Yellow
    $fullTenantName = Read-Host "Enter the full tenant name (e.g. contoso.onmicrosoft.com)"
    $spoTenantName = $fullTenantName -replace '\.onmicrosoft\.com$', ''
}
Write-Host "NOTE: verify that '$spoTenantName' matches your actual SharePoint URL (https://$spoTenantName.sharepoint.com) - tenants that have been renamed can differ from the initial domain." -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 4. Values that cannot be derived - prompt unless provided as parameters
# ---------------------------------------------------------------------------
if ([string]::IsNullOrEmpty($ServiceAccountUPN)) {
    $ServiceAccountUPN = Read-Host "Service account UPN (standard licensed user - used to authorise the delegated API connections)"
}

# Validate that the service account exists - deploy.ps1 uses it as site owner and
# fails without it. Re-prompt interactively; warn only in unattended (-Force) runs.
while (-not [string]::IsNullOrWhiteSpace($ServiceAccountUPN)) {
    $saUserJson = az ad user show --id $ServiceAccountUPN 2>$null
    $saUser = if ($saUserJson) { $saUserJson | ConvertFrom-Json } else { $null }
    if ($null -ne $saUser) {
        Write-Host "Service account verified: $($saUser.displayName) ($ServiceAccountUPN)" -ForegroundColor Green
        break
    }
    Write-Host "Service account '$ServiceAccountUPN' was not found in the tenant." -ForegroundColor Yellow
    if ($Force) {
        Write-Host "Continuing anyway (-Force) - create the account before running deploy.ps1, which validates it again." -ForegroundColor Yellow
        break
    }
    $retry = Read-Host "Re-enter the UPN, or press enter to keep '$ServiceAccountUPN' anyway (the account must exist before deploy.ps1 runs)"
    if ([string]::IsNullOrWhiteSpace($retry)) { break }
    $ServiceAccountUPN = $retry
}
# ---------------------------------------------------------------------------
# 5. Build parameters.json from the template (keeps descriptions and any new
#    parameters in sync) and fill in the derived/prompted values
# ---------------------------------------------------------------------------
$parameters = Get-Content $templatePath -Raw | ConvertFrom-Json

$values = @{
    tenantId          = $account.tenantId
    subscriptionId    = $account.id
    fullTenantName    = $fullTenantName
    spoTenantName     = $spoTenantName
    region            = $Region
    serviceAccountUPN = $ServiceAccountUPN
    enableSensitivity = [bool]$EnableSensitivity
}

foreach ($name in $values.Keys) {
    if ($parameters.PSObject.Properties.Name -contains $name) {
        $parameters.$name.Value = $values[$name]
    }
}

# ---------------------------------------------------------------------------
# 6. Check the PnP app registration in the target tenant, so the next-steps
#    output can say exactly what is - and is not - needed.
#
#    This is the only app registration the solution needs: everything at runtime
#    authenticates with managed identity. The Bestillingsportalen Entra ID app was
#    removed together with the sensitivity label ROPC flow.
# ---------------------------------------------------------------------------
Write-Host "Checking app registrations in the tenant..." -ForegroundColor Yellow

# PnP PowerShell app (installation identity) - the default pnpAppId is the
# Prosjektportalen PnP app, present in tenants where Prosjektportalen 365 is installed.
$pnpSpJson = az ad sp show --id $parameters.pnpAppId.Value 2>$null
$pnpSp = if ($pnpSpJson) { $pnpSpJson | ConvertFrom-Json } else { $null }
if ($null -ne $pnpSp) {
    Write-Host "PnP app found: '$($pnpSp.displayName)' ($($parameters.pnpAppId.Value)) - pnpAppId can be used as-is; deploy.ps1 signs in interactively." -ForegroundColor Green
}
else {
    Write-Host "The PnP app ($($parameters.pnpAppId.Value)) is NOT present in this tenant. Register one with Register-PnPEntraIDAppForInteractiveLogin (see 'PnP PowerShell App Registration' in the Deployment guide) and update pnpAppId in the generated file." -ForegroundColor Yellow
}

if ((Test-Path $OutputPath) -and -not $Force) {
    Write-Host ""
    Write-Host "$OutputPath already exists." -ForegroundColor Yellow
    $overwrite = Read-Host "Overwrite it? ( y / n )"
    if ($overwrite -ne "y") {
        Write-Host "Aborted - nothing written." -ForegroundColor Yellow
        exit 0
    }
}

$parameters | ConvertTo-Json -Depth 5 | Set-Content $OutputPath -Encoding utf8NoBOM

# ---------------------------------------------------------------------------
# 7. Summary and next steps
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "#################### GENERATED PARAMETERS ####################" -ForegroundColor Magenta
foreach ($property in $parameters.PSObject.Properties) {
    $value = $property.Value.Value
    $display = if ($null -eq $value -or "$value" -eq "") { "(blank)" } else { "$value" }
    Write-Host ("  {0,-22}{1}" -f "$($property.Name):", $display)
}
Write-Host "##############################################################" -ForegroundColor Magenta
Write-Host ""
Write-Host "Written to $OutputPath" -ForegroundColor Green
Write-Host ""
Write-Host "Review the file - especially the defaulted names (resourceGroupName, requestsSiteName)." -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan

if ($null -eq $pnpSp) {
    Write-Host "  - Register a PnP PowerShell app with Register-PnPEntraIDAppForInteractiveLogin (see 'PnP PowerShell" -ForegroundColor Cyan
    Write-Host "    App Registration' in the Deployment guide) and update pnpAppId in $OutputPath before running deploy.ps1." -ForegroundColor Cyan
}

Write-Host "  1. Run ./deploy.ps1 - the pre-flight summary shows the target environment before anything is created." -ForegroundColor Cyan
