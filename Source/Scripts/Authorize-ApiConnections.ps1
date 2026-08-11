<#
.SYNOPSIS
    Guided authorisation of the delegated API connections (bestillingsportalen-spo,
    -o365, -o365users, -teams).

.DESCRIPTION
    The four delegated API connections must be authorised interactively with the
    SERVICE ACCOUNT - that part cannot be automated (delegated OAuth requires the
    account itself to sign in; there is no supported way to consent on behalf of a
    user). This script automates everything around it:

      1. Checks the status of each connection (skips the ones already Connected).
      2. Generates a consent link via the ARM listConsentLinks API and opens it in
         the browser - sign in AS THE SERVICE ACCOUNT and complete the consent.
      3. Captures the consent code on a local listener (http://localhost:8155/)
         and completes the authorisation via the ARM confirmConsentCode API.
      4. Re-checks and reports the final status of all four connections.

    Run it after deploy.ps1, signed in to the Azure CLI with access to the resource
    group (deploy.ps1 leaves you signed in). Re-run it any time - for example after
    an upgrade, if a connection has flipped to Error.

    If the consent-link flow fails for a connection, fall back to the Azure Portal:
    resource group -> the connection -> Edit API connection -> Authorize.

.PARAMETER ResourceGroupName
    Resource group containing the API connections. Default: rg-bestillingsportalen.

.PARAMETER SubscriptionId
    Subscription id. Defaults to the Azure CLI's current subscription.

.EXAMPLE
    ./Authorize-ApiConnections.ps1

.EXAMPLE
    ./Authorize-ApiConnections.ps1 -ResourceGroupName rg-bestillingsportalen
#>
param
(
    [string]$ResourceGroupName = "rg-bestillingsportalen",
    [string]$SubscriptionId
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "Azure CLI is not installed - install it and sign in with az login first." -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrEmpty($SubscriptionId)) {
    $SubscriptionId = az account show --query id --output tsv 2>$null
    if ([string]::IsNullOrEmpty($SubscriptionId)) {
        Write-Host "Not signed in to the Azure CLI - run az login first." -ForegroundColor Red
        exit 1
    }
}

$connections = @('bestillingsportalen-o365', 'bestillingsportalen-o365users', 'bestillingsportalen-spo', 'bestillingsportalen-teams')
$apiVersion = "2016-06-01"
$redirectUrl = "http://localhost:8155/"

function Get-ConnectionStatus([string]$Name) {
    $json = az rest --method get --url "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/connections/$Name`?api-version=$apiVersion" 2>$null
    if (-not $json) { return $null }
    return (($json | ConvertFrom-Json).properties.statuses | Select-Object -First 1).status
}

Write-Host "Checking the delegated API connections in $ResourceGroupName..." -ForegroundColor Yellow
Write-Host "NOTE: sign in AS THE SERVICE ACCOUNT in the browser windows that open - not your admin account." -ForegroundColor Cyan
Write-Host ""

foreach ($connection in $connections) {
    $status = Get-ConnectionStatus $connection
    if ($null -eq $status) {
        Write-Host "[$connection] Not found in $ResourceGroupName - has deploy.ps1 been run?" -ForegroundColor Red
        continue
    }
    if ($status -eq 'Connected') {
        Write-Host "[$connection] Already Connected - skipping." -ForegroundColor Green
        continue
    }

    Write-Host "[$connection] Status: $status - generating consent link..." -ForegroundColor Yellow
    $bodyPath = Join-Path ([System.IO.Path]::GetTempPath()) "bp-consent-body.json"
    "{""parameters"":[{""parameterName"":""token"",""redirectUrl"":""$redirectUrl""}]}" | Set-Content $bodyPath
    $consentJson = az rest --method post --url "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/connections/$connection/listConsentLinks?api-version=$apiVersion" --headers "Content-Type=application/json" --body "@$bodyPath" 2>$null
    Remove-Item $bodyPath -ErrorAction SilentlyContinue

    $consentLink = if ($consentJson) { (($consentJson | ConvertFrom-Json).value | Select-Object -First 1).link } else { $null }
    if ([string]::IsNullOrEmpty($consentLink)) {
        Write-Host "[$connection] Could not generate a consent link - authorise it manually in the Azure Portal (Edit API connection -> Authorize)." -ForegroundColor Red
        continue
    }

    $listener = $null
    try {
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add($redirectUrl)
        $listener.Start()
    }
    catch {
        Write-Host "[$connection] Could not listen on $redirectUrl ($($_.Exception.Message)) - close whatever is using the port and re-run." -ForegroundColor Red
        if ($listener) { $listener.Close() }
        continue
    }

    Write-Host "[$connection] Opening the consent link in your browser - sign in as the service account and complete the consent." -ForegroundColor Yellow
    Write-Host "[$connection] Expect a 'created from a different organization'/phishing warning: the link was generated by YOUR admin session while the service account consents. Tick 'I have verified this request' and Allow access." -ForegroundColor Cyan
    Start-Process $consentLink

    # Wait for the consent redirect to hit the local listener. Two variants exist:
    # the redirect carries a ?code= we must confirm ourselves, or apihub has already
    # completed the consent server-side (its cross-user confirmation page) and the
    # redirect arrives without a code.
    $consentCode = $null
    $redirectSeen = $false
    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    while ([DateTime]::UtcNow -lt $deadline) {
        $contextTask = $listener.GetContextAsync()
        $remaining = $deadline - [DateTime]::UtcNow
        if (-not $contextTask.Wait([TimeSpan]::FromSeconds([Math]::Max(1, $remaining.TotalSeconds)))) { break }
        $context = $contextTask.Result
        $consentCode = $context.Request.QueryString["code"]
        $redirectSeen = $true
        $buffer = [System.Text.Encoding]::UTF8.GetBytes("<html><body style=""font-family:sans-serif""><h3>Consent for $connection received - you can close this tab.</h3></body></html>")
        $context.Response.ContentType = "text/html"
        $context.Response.OutputStream.Write($buffer, 0, $buffer.Length)
        $context.Response.Close()
        break
    }
    $listener.Close()

    if (-not $redirectSeen) {
        Write-Host "[$connection] No consent redirect received within 5 minutes - re-run this script or authorise it in the Azure Portal." -ForegroundColor Yellow
        continue
    }

    if ($consentCode) {
        # Complete the authorisation server-side with the captured code.
        $confirmPath = Join-Path ([System.IO.Path]::GetTempPath()) "bp-consent-confirm.json"
        "{""code"":""$consentCode""}" | Set-Content $confirmPath
        az rest --method post --url "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/connections/$connection/confirmConsentCode?api-version=$apiVersion" --headers "Content-Type=application/json" --body "@$confirmPath" --output none 2>$null
        Remove-Item $confirmPath -ErrorAction SilentlyContinue
    }

    $status = $null
    foreach ($delay in 1, 2, 3, 5) {
        $status = Get-ConnectionStatus $connection
        if ($status -eq 'Connected') { break }
        Start-Sleep -Seconds $delay
    }
    if ($status -eq 'Connected') {
        Write-Host "[$connection] Connected." -ForegroundColor Green
    }
    else {
        Write-Host "[$connection] Still '$status' - the consent may need a few more seconds, or it failed. Re-run this script or authorise it in the Azure Portal." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "#################### CONNECTION STATUS ####################" -ForegroundColor Magenta
$allConnected = $true
foreach ($connection in $connections) {
    $status = Get-ConnectionStatus $connection
    $color = if ($status -eq 'Connected') { 'Green' } elseif ($null -eq $status) { 'Red' } else { 'Yellow' }
    if ($status -ne 'Connected') { $allConnected = $false }
    Write-Host ("  [{0,-10}] {1}" -f $(if ($null -eq $status) { 'NOT FOUND' } else { $status }), $connection) -ForegroundColor $color
}
Write-Host "###########################################################" -ForegroundColor Magenta
if ($allConnected) {
    Write-Host "All four delegated API connections are authorised." -ForegroundColor Green
}
else {
    Write-Host "Some connections are not Connected yet - re-run this script, or authorise them in the Azure Portal (Edit API connection -> Authorize)." -ForegroundColor Yellow
}
