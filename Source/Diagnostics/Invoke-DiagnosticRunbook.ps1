# Laster opp et diagnoseskript som runbook i Automation-kontoen, starter det og skriver ut resultatet.
#
# Bruker samme REST-kall som deploy.ps1 (api-version 2024-10-23: draft/content + publish), så
# runbooken beholder runtime environmentet 'bestillingsportalen-ps74'. Import-AzAutomationRunbook
# kan sette runbooken tilbake til PowerShell 5.1, og da finnes ikke PnP.PowerShell 3.x.
#
# Finnes ikke runbooken, opprettes den på riktig runtime environment. Finnes den, erstattes
# innholdet og den publiseres på nytt.
#
# Forutsetninger: Az PowerShell (Az.Accounts, Az.Automation). Logg inn med Connect-AzAccount
# mot riktig tenant og abonnement først. Kontoen trenger Automation Contributor eller tilsvarende.
# Ressursgruppen finnes automatisk ved å slå opp Automation-kontoen i valgt abonnement.
#
# Eksempel:
#   Connect-AzAccount -Tenant contoso.onmicrosoft.com -Subscription <abonnement>
#   .\Invoke-DiagnosticRunbook.ps1 -ScriptPath .\Test-GroupSiteLanguageRetry.ps1 -Parameters @{
#       AdminUrl = 'https://contoso-admin.sharepoint.com'; Owner = 'ola@contoso.com'
#       Alias = 'langtest-01'; Lcid = 1053; BatchSize = 5; MaxRounds = 3; ManagedIdentity = $true }

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true)]  [string]    $ScriptPath,
    [Parameter(Mandatory = $false)] [hashtable] $Parameters = @{},
    # Standard: filnavnet uten .ps1
    [Parameter(Mandatory = $false)] [string]    $RunbookName,
    [Parameter(Mandatory = $false)] [string]    $ResourceGroupName,
    [Parameter(Mandatory = $false)] [string]    $AutomationAccountName = 'bestillingsportalen-auto',
    [Parameter(Mandatory = $false)] [string]    $RuntimeEnvironment = 'bestillingsportalen-ps74',
    # Last ikke opp på nytt, bare start runbooken som den er
    [Parameter(Mandatory = $false)] [switch]    $SkipUpload,
    # Start jobben og avslutt uten å vente på resultatet
    [Parameter(Mandatory = $false)] [switch]    $NoWait,
    [Parameter(Mandatory = $false)] [int]       $TimeoutMinutes = 90
)

$ErrorActionPreference = 'Stop'
$api = 'api-version=2024-10-23'
$jobApi = 'api-version=2023-11-01'

$ScriptPath = (Resolve-Path $ScriptPath).Path
if (-not $RunbookName) { $RunbookName = [IO.Path]::GetFileNameWithoutExtension($ScriptPath) }

$ctx = Get-AzContext
if (-not $ctx) { throw 'Ikke innlogget. Kjør Connect-AzAccount -Tenant <tenant> -Subscription <abonnement> først.' }

if (-not $ResourceGroupName) {
    $account = Get-AzAutomationAccount | Where-Object AutomationAccountName -eq $AutomationAccountName | Select-Object -First 1
    if (-not $account) { throw "Fant ikke Automation-kontoen '$AutomationAccountName' i abonnementet '$($ctx.Subscription.Name)'. Bytt med Set-AzContext, eller oppgi -ResourceGroupName." }
    $ResourceGroupName = $account.ResourceGroupName
}

$accountUrl = "https://management.azure.com/subscriptions/$($ctx.Subscription.Id)/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName"
$runbookUrl = "$accountUrl/runbooks/$RunbookName"
Write-Host "Automation-konto: $AutomationAccountName ($ResourceGroupName, $($ctx.Subscription.Name))" -ForegroundColor Cyan
Write-Host "Runbook        : $RunbookName" -ForegroundColor Cyan

function Get-ArmHeaders([string] $ContentType = 'application/json') {
    # Az.Accounts 5.x returnerer tokenet som SecureString
    $t = (Get-AzAccessToken -ResourceUrl 'https://management.azure.com/' -AsSecureString).Token
    $plain = [System.Net.NetworkCredential]::new('', $t).Password
    return @{ Authorization = "Bearer $plain"; 'Content-Type' = $ContentType }
}
function Invoke-Arm([string] $Method, [string] $Url, $Body, [string] $ContentType = 'application/json') {
    $req = @{ Method = $Method; Uri = $Url; Headers = (Get-ArmHeaders $ContentType) }
    if ($null -ne $Body) {
        $req.Body = if ($Body -is [string]) { [Text.Encoding]::UTF8.GetBytes($Body) } else { [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 6)) }
    }
    return Invoke-RestMethod @req
}

# ---------------------------------------------------------------------------
# Last opp og publiser
# ---------------------------------------------------------------------------
if (-not $SkipUpload) {
    $runbook = $null
    try { $runbook = Invoke-Arm Get "$runbookUrl`?$api" } catch { }
    if (-not $runbook) {
        Write-Host "Oppretter runbooken på $RuntimeEnvironment" -ForegroundColor Yellow
        $location = (Invoke-Arm Get "$accountUrl`?$api").location
        Invoke-Arm Put "$runbookUrl`?$api" @{
            location   = $location
            properties = @{ runbookType = 'PowerShell'; runtimeEnvironment = $RuntimeEnvironment; logVerbose = $false; logProgress = $false; draft = @{} }
        } | Out-Null
    }

    Write-Host 'Laster opp innhold og publiserer' -ForegroundColor Yellow
    Invoke-Arm Put "$runbookUrl/draft/content?$api" ([IO.File]::ReadAllText($ScriptPath)) 'text/powershell' | Out-Null
    Invoke-Arm Post "$runbookUrl/publish?$api" $null | Out-Null

    # Publisering er asynkron. Vent til runbooken er publisert før jobben startes.
    $end = (Get-Date).AddMinutes(2)
    do {
        Start-Sleep -Seconds 3
        $runbook = Invoke-Arm Get "$runbookUrl`?$api"
    } while ($runbook.properties.state -ne 'Published' -and (Get-Date) -lt $end)
    Write-Host "Status: $($runbook.properties.state), runtime environment: $($runbook.properties.runtimeEnvironment)"
    if ($runbook.properties.runtimeEnvironment -ne $RuntimeEnvironment) {
        Write-Warning "Runbooken står på '$($runbook.properties.runtimeEnvironment)', ikke '$RuntimeEnvironment'. Koble den om under Automation-kontoen > Runtime environments."
    }
}

# ---------------------------------------------------------------------------
# Start jobben
# ---------------------------------------------------------------------------
# Jobbparametre sendes som tekst. Brytere og bool som 'true'/'false'.
$jobParams = @{}
foreach ($k in $Parameters.Keys) {
    $v = $Parameters[$k]
    $jobParams[$k] = if ($v -is [bool] -or $v -is [switch]) { ([bool] $v).ToString().ToLowerInvariant() } else { "$v" }
}
$jobId = [guid]::NewGuid().ToString()
$jobUrl = "$accountUrl/jobs/$jobId"
Invoke-Arm Put "$jobUrl`?$jobApi" @{ properties = @{ runbook = @{ name = $RunbookName }; parameters = $jobParams } } | Out-Null
Write-Host "Jobb startet: $jobId" -ForegroundColor Green

if ($NoWait) {
    Write-Host "Følg jobben i portalen: Automation-kontoen > Jobs > $jobId"
    return
}

# ---------------------------------------------------------------------------
# Vent og skriv ut resultatet
# ---------------------------------------------------------------------------
$end = (Get-Date).AddMinutes($TimeoutMinutes)
$status = $null
$job = $null
while ((Get-Date) -lt $end) {
    $job = Invoke-Arm Get "$jobUrl`?$jobApi"
    if ($job.properties.status -ne $status) { $status = $job.properties.status; Write-Host ("[{0:HH:mm:ss}] Status: {1}" -f (Get-Date), $status) }
    if ($status -in @('Completed', 'Failed', 'Stopped', 'Suspended')) { break }
    Start-Sleep -Seconds 10
}

Write-Host ''
Write-Host '=== Output ===' -ForegroundColor Cyan
Invoke-RestMethod -Method Get -Uri "$jobUrl/output?$jobApi" -Headers (Get-ArmHeaders)

if ($status -ne 'Completed') {
    if ($job.properties.exception) { Write-Host "Feil: $($job.properties.exception)" -ForegroundColor Red }
    Write-Host "Jobben endte med status '$status'. Se Error-strømmen i portalen for detaljer." -ForegroundColor Red
}
