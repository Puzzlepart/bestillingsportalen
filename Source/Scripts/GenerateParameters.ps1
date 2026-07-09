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
        keyVaultName    - default name, availability-checked; a unique fallback is
                          generated when the default is taken in another tenant

    Everything else gets a sensible default from parameters.template.json. Values that
    cannot be derived (service account UPN, PnP certificate path) are prompted for -
    or can be passed as parameters for unattended use.

    The script only reads from Azure - it changes nothing in the environment.

.PARAMETER OutputPath
    Where to write the generated file. Default: .\parameters.json (next to deploy.ps1).

.PARAMETER ServiceAccountUPN
    UPN of the service account used for the delegated API connections. Prompted for when omitted.

.PARAMETER PnpCertPath
    Path to the PnP PowerShell certificate. Prompted for when omitted (can be left blank).

.PARAMETER Region
    Azure region for the resources. Default: norwayeast.

.PARAMETER EnableSensitivity
    Enable the sensitivity label functionality (requires a service account without MFA).

.PARAMETER Force
    Overwrite an existing parameters.json without asking.

.EXAMPLE
    ./GenerateParameters.ps1

.EXAMPLE
    ./GenerateParameters.ps1 -ServiceAccountUPN svc-bp@contoso.com -Region westeurope -Force
#>
param
(
    [string]$OutputPath = ".\parameters.json",
    [string]$ServiceAccountUPN,
    [string]$PnpCertPath,
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
# 1. Azure CLI context (sign in if needed, pick subscription when several)
# ---------------------------------------------------------------------------
Write-Host "Checking Azure CLI sign-in..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
if ($null -eq $account) {
    Write-Host "Not signed in - launching az login..." -ForegroundColor Yellow
    az login | Out-Null
    $account = az account show | ConvertFrom-Json
}

$subscriptions = @(az account list --query "[?state=='Enabled']" --output json | ConvertFrom-Json)
if ($subscriptions.Count -eq 0) {
    Write-Host "No enabled subscriptions found for the signed-in account." -ForegroundColor Red
    exit 1
}
if ($subscriptions.Count -gt 1) {
    Write-Host ""
    Write-Host "You have access to several subscriptions:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        $marker = if ($subscriptions[$i].id -eq $account.id) { " (current)" } else { "" }
        Write-Host ("  [{0}] {1} - {2} (tenant {3}){4}" -f $i, $subscriptions[$i].name, $subscriptions[$i].id, $subscriptions[$i].tenantId, $marker)
    }
    $choice = Read-Host "Select the subscription to deploy to (0-$($subscriptions.Count - 1), enter for current)"
    if (-not [string]::IsNullOrWhiteSpace($choice)) {
        $selected = $subscriptions[[int]$choice]
        az account set --subscription $selected.id
        $account = az account show | ConvertFrom-Json
    }
}

Write-Host "Using subscription '$($account.name)' ($($account.id)) in tenant $($account.tenantId)" -ForegroundColor Green

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
# 3. Key Vault name - availability-checked, unique fallback when taken
# ---------------------------------------------------------------------------
function Test-KeyVaultNameAvailable([string]$Name) {
    $body = (@{ name = $Name; type = "Microsoft.KeyVault/vaults" } | ConvertTo-Json -Compress).Replace('"', '\"')
    $result = az rest --method post --url "https://management.azure.com/subscriptions/$($account.id)/providers/Microsoft.KeyVault/checkNameAvailability?api-version=2022-07-01" --body $body 2>$null | ConvertFrom-Json
    return $result
}

Write-Host "Checking Key Vault name availability..." -ForegroundColor Yellow
$keyVaultName = "kv-bestillingsportalen"
$kvCheck = Test-KeyVaultNameAvailable $keyVaultName
if ($null -ne $kvCheck -and -not $kvCheck.nameAvailable) {
    if ($kvCheck.reason -eq 'AlreadyExists') {
        # The name may be taken by this solution in THIS subscription (re-generation) - that is fine for deploy.ps1.
        $existing = az keyvault show --name $keyVaultName --query id --output tsv 2>$null
        if (-not [string]::IsNullOrEmpty($existing)) {
            Write-Host "Key Vault '$keyVaultName' already exists in this subscription (existing installation) - keeping the name; deploy.ps1 will prompt about reuse." -ForegroundColor Yellow
        }
        else {
            # Taken elsewhere - derive a unique fallback (Key Vault names: 3-24 chars, globally unique)
            $fallback = ("kv-bp-$spoTenantName" -replace '[^a-zA-Z0-9-]', '')
            if ($fallback.Length -gt 24) { $fallback = $fallback.Substring(0, 24).TrimEnd('-') }
            $fbCheck = Test-KeyVaultNameAvailable $fallback
            if ($null -ne $fbCheck -and $fbCheck.nameAvailable) {
                $keyVaultName = $fallback
            }
            else {
                $keyVaultName = ("kv-bp-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
            }
            Write-Host "Default Key Vault name is taken in another subscription/tenant - using '$keyVaultName' instead." -ForegroundColor Yellow
        }
    }
}
Write-Host "Key Vault name: $keyVaultName" -ForegroundColor Green

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
if ([string]::IsNullOrEmpty($PnpCertPath)) {
    $PnpCertPath = Read-Host "Path to your PnP PowerShell certificate (leave blank to use interactive PnP sign-in)"
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
    keyVaultName      = $keyVaultName
    region            = $Region
    serviceAccountUPN = $ServiceAccountUPN
    pnpCertPath       = $PnpCertPath
    enableSensitivity = [bool]$EnableSensitivity
}

foreach ($name in $values.Keys) {
    if ($parameters.PSObject.Properties.Name -contains $name) {
        $parameters.$name.Value = $values[$name]
    }
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
# 6. Summary and next steps
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
Write-Host "Review the file - especially the defaulted names (resourceGroupName, appName, requestsSiteName) - then:" -ForegroundColor Cyan
Write-Host "  1. Run ./createentraidapp.ps1 -AppName '$($parameters.appName.Value)' (requires Global Administrator)" -ForegroundColor Cyan
Write-Host "  2. Run ./deploy.ps1 - the pre-flight summary will show the target environment before anything is created" -ForegroundColor Cyan
