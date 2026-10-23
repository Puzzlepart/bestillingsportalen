<#
.SYNOPSIS
    Read-only verification of an installed Bestillingsportalen environment: runs a
    checklist against SharePoint, the SPFx packages, the managed identities' app roles,
    the Automation account, the API connections and the Logic Apps, and prints OK /
    MISSING / WARNING / SKIPPED per item with a concrete Fix line.

.DESCRIPTION
    Run it after deploy.ps1 and Authorize-ApiConnections.ps1, before the test order in
    Configuration-guide.md (Steg 8). It answers "is everything in place?" in one run,
    instead of clicking through the SharePoint admin center, the Azure portal and Entra ID.

    Without -TriggerLogicApps and -TestProvision the script NEVER creates, changes or
    deletes anything in the environment. Every lookup is a read; a lookup that fails is reported as UNKNOWN
    or WARNING, never as a crash, and the remaining checks still run. The only local
    change is the Azure CLI's default subscription, which is switched to the target for
    the run and restored at the end.

    Same inputs and sign-ins as deploy.ps1: the parameter file (-ParametersPath), PnP
    interactive sign-in with the PnP app (pnpAppId) and the Azure CLI. Az PowerShell is
    not used. Needs SharePoint Administrator, and Reader on the resource group.

    What cannot be checked from here - the Power Automate approval flow and the
    end-to-end test order - is listed as SKIPPED with what to check by hand.

    Exit code 0 when nothing is MISSING, 1 otherwise.

.PARAMETER ParametersPath
    Path to the parameter file the environment was deployed from. Default:
    .\parameters.json - the same file deploy.ps1 uses.

.PARAMETER SharePointOnly
    Check ONLY the SharePoint part: the site, lists, registry, service account and SPFx
    packages. For an environment installed with deploy.ps1 -SharePointOnly where the
    Azure part is not in place yet. No subscription access is needed.

.PARAMETER TriggerLogicApps
    Also RUN the logic apps that run on a schedule (Recurrence trigger: GetHubSites,
    GetSiteTemplates, GetTeamsTemplates, SyncGroupSettings, SyncLabels - found from
    their definitions, so a customer's own scheduled logic app is included), wait for
    each run to finish and report the result: succeeded, or which action failed and
    why. This is Configuration-guide.md Steg 4 in one go, and the quickest way to see
    that the app roles and API connections actually work.

    This is the one thing the script changes: the runs do what they do on their weekly
    schedule - fill the Hub Sites, Site Templates, Teams Templates and IP Labels lists
    and sync the group settings. Needs Logic App Contributor (or Contributor) on the
    resource group; Reader is enough for everything else. Disabled logic apps are not
    started. Cannot be combined with -SharePointOnly.

.PARAMETER LogicAppTimeoutMinutes
    With -TriggerLogicApps: how long to wait for the runs, in total. Default 10. A run
    still going after that is reported as a WARNING with where to follow it - it is not
    cancelled. Ctrl+C stops the script, not the runs: they finish in Azure regardless.

.PARAMETER TestProvision
    Also ORDER a space through the 'Provisioning Requests' list, the same way the
    ordering web part does, follow it until it is created (or fails) and then DELETE it.
    This tests the provisioning end to end: the ProcessProvisionRequest logic app, the
    group or site creation, the ConfigureSpace runbook and - unless auto approval is on -
    the approval flow.

    - The request gets the same fields as one from the web part, with the account signed
      in to SharePoint as owner and requester, a generated name ('BP-test <time>') and
      alias ('bptest<time>'), Private visibility and no guests.
    - Approval follows the 'EnableAutoApproval' setting, like the web part: 'Approved'
      right away when it is on, otherwise 'Submitted' - and then someone has to approve
      the request (Teams or Approvals) while the script waits.
    - Afterwards the test space is deleted: a Microsoft 365 group is deleted (soft - it
      can be restored for 30 days, and its site goes with it), a plain site goes to the
      recycle bin. A request that never got past approval is deleted, so a late approval
      cannot create anything. A request still being provisioned at the timeout is left
      alone - deleting under the logic app's feet would only leave debris - and the
      script says what to delete afterwards. The request item itself is kept as a record.
    - Welcome e-mail and Teams messages go to the signed-in account, as for any order.

    Needs the Azure CLI signed in (the group is deleted over Graph) and edit rights on
    the requests site. Cannot be combined with -SharePointOnly.

.PARAMETER TestProvisionType
    With -TestProvision: the provisioning type to order, as its InternalTitle (as in
    SpaceTypeInternal) or Title in the 'Provisioning Types' list. Default 'Office 365
    Group' - a Microsoft 365 group with a site, no Teams, no hub. Types that join a hub
    or apply a template are not supported (yet), and are refused before anything is
    created.

.PARAMETER TestProvisionTimeoutMinutes
    With -TestProvision: how long to wait for the order to finish. Default 30 - a group
    usually takes 10-15 minutes, and without auto approval the wait includes the
    approval.

.EXAMPLE
    ./Test-Installation.ps1

.EXAMPLE
    ./Test-Installation.ps1 -TriggerLogicApps -TestProvision
    Check everything, run the scheduled logic apps, then order a test space, follow it to
    'Space Created' and delete it.

.EXAMPLE
    ./Test-Installation.ps1 -TriggerLogicApps
    Check everything, and run the scheduled logic apps and wait for the results.

.EXAMPLE
    ./Test-Installation.ps1 -ParametersPath .\parameters-contoso.json

.EXAMPLE
    ./Test-Installation.ps1 -SharePointOnly
    After deploy.ps1 -SharePointOnly: check the SharePoint part, skip Azure.
#>
param
(
    [Parameter(Mandatory = $false)]
    [string]$ParametersPath = ".\parameters.json", # Parameter file the environment was deployed from
    [switch]$SharePointOnly, # Check the SharePoint part only - see the help
    [switch]$TriggerLogicApps, # Also run the scheduled logic apps and wait for the results - see the help
    [ValidateRange(1, 120)]
    [int]$LogicAppTimeoutMinutes = 10, # With -TriggerLogicApps: total wait for the runs
    [switch]$TestProvision, # Also order a test space, follow it and delete it - see the help
    [string]$TestProvisionType = 'Office 365 Group', # With -TestProvision: InternalTitle or Title in 'Provisioning Types'
    [ValidateRange(5, 240)]
    [int]$TestProvisionTimeoutMinutes = 30 # With -TestProvision: wait for the order to finish
)

if ($SharePointOnly -and ($TriggerLogicApps -or $TestProvision)) {
    Write-Host "$(if ($TriggerLogicApps) { '-TriggerLogicApps' } else { '-TestProvision' }) cannot be combined with -SharePointOnly: the logic apps are part of the Azure installation." -ForegroundColor Red
    exit 1
}

# Every lookup handles its own failure (try/catch, -ErrorAction Stop where it matters)
$ErrorActionPreference = "Continue"

# Same requirement as deploy.ps1: PnP.PowerShell 3.x needs PowerShell 7.4
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version]'7.4') {
    Write-Host "This script requires PowerShell 7.4 or newer (current: $($PSVersionTable.PSVersion)). Install the latest PowerShell from https://aka.ms/powershell and re-run in a new session." -ForegroundColor Red
    exit 1
}

$resolvedParametersPath = Resolve-Path -LiteralPath $ParametersPath -ErrorAction SilentlyContinue
if ($null -eq $resolvedParametersPath) {
    Write-Host "Parameter file '$ParametersPath' was not found - point -ParametersPath at the file the environment was deployed from." -ForegroundColor Red
    exit 1
}
$ParametersPath = $resolvedParametersPath.Path
$parametersFileName = Split-Path -Leaf $ParametersPath

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "Azure CLI is not installed - install it from https://learn.microsoft.com/cli/azure/install-azure-cli and re-run in a new PowerShell session." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# What a complete installation consists of. Names mirror deploy.ps1 - keep them in
# sync when the solution changes. The app role sets are NOT listed here: they are read
# from AssignPermissionsToManagedIdentity.ps1, see GetExpectedAppRoles.
# ---------------------------------------------------------------------------
$requestSettingsListName = "Provisioning Request Settings"
$expectedLists = @(
    "Provisioning Requests",
    $requestSettingsListName,
    "Provisioning Types",
    "Site Templates",
    "Hub Sites",
    "Teams Templates",
    "IP Labels",
    "Guest Requests"
)
$installedVersionSettingName = "InstalledVersion"
$installedDateSettingName = "InstalledDate"
$registryKey = "bp_ProvisionUrls"

$automationAccountName = "bestillingsportalen-auto"
$runtimeEnvironmentName = "bestillingsportalen-ps74" # Keep in sync with runbooks.bicep
$uamiName = "bestillingsportalen-uami" # Overridden by the uamiName parameter in the parameter file if present
# The runbooks DeployLocalRunbooks publishes from Source/Runbooks/. CustomerSpecific is
# created once and customer-owned, so it is checked separately.
$repoRunbooks = @('ConfigureSpace', 'GetSiteTemplates', 'AddGuestToSite', 'CreateGroupWithLanguage')
$customerRunbook = 'CustomerSpecific'
# The four delegated connections (authorised as the service account) and the managed
# identity connection to Azure Automation - all from apiconnections.json
$delegatedConnections = @('bestillingsportalen-o365', 'bestillingsportalen-o365users', 'bestillingsportalen-spo', 'bestillingsportalen-teams')
$automationConnection = 'bestillingsportalen-automation'
# The logic apps DeployARMTemplates deploys. The support ones are run once by hand after
# the installation (Configuration-guide.md Steg 4) - never having run is worth a warning.
$expectedLogicApps = @('ProcessGuests', 'CheckSiteExists', 'ProcessProvisionRequest', 'ProcessGuestRequest', 'SyncGroupSettings', 'GetSiteTemplates', 'GetHubSites', 'SyncLabels', 'GetTeamsTemplates')
$supportLogicApps = @('GetHubSites', 'GetSiteTemplates', 'GetTeamsTemplates', 'SyncGroupSettings', 'SyncLabels')

$graphAppId = '00000003-0000-0000-c000-000000000000'
$spoAppId = '00000003-0000-0ff1-ce00-000000000000'
# Managed identity tokens carry the roles from when they were issued, and are cached for
# up to ~24 hours - see the note in Configuration-guide.md Steg 8
$tokenCacheHours = 24

$spfxRoot = Join-Path $PSScriptRoot "..\SharePointFramework"
$assignScriptPath = Join-Path $PSScriptRoot "AssignPermissionsToManagedIdentity.ps1"

# VERSION in the repo root, as deploy.ps1 reads it
$repoVersion = $null
$versionFilePath = Join-Path $PSScriptRoot "..\..\VERSION"
if (Test-Path $versionFilePath) {
    $rawVersion = "$(Get-Content $versionFilePath -Raw -ErrorAction SilentlyContinue)".Trim()
    if ($rawVersion -match '^\d+\.\d+\.\d+$') { $repoVersion = $rawVersion }
}

# ---------------------------------------------------------------------------
# Checklist - the same look as deploy.ps1's PRE-DEPLOYMENT CHECKLIST
# (RecordPreflightCheck / ShowPreflightChecklist). Every check records its result
# instead of stopping, so one run shows everything. SKIPPED items carry what to check
# by hand, so their second line reads "Check:" instead of "Fix:".
# ---------------------------------------------------------------------------
$script:checks = @()

function RecordCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('OK', 'MISSING', 'WARNING', 'SKIPPED', 'UNKNOWN')][string]$Status,
        [string]$Detail = '',
        [string]$Fix = ''
    )
    $script:checks += [pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail; Fix = $Fix }
}

# Renders the checklist and returns the number of MISSING items.
function ShowChecklist {
    Write-Host ""
    Write-Host "################## POST-INSTALLATION CHECKLIST ###################" -ForegroundColor Magenta
    foreach ($check in $script:checks) {
        $color = switch ($check.Status) {
            'OK' { 'Green' }
            'MISSING' { 'Red' }
            'WARNING' { 'Yellow' }
            'SKIPPED' { 'DarkGray' }
            'UNKNOWN' { 'Yellow' }
        }
        $line = "  [{0,-7}] {1}" -f $check.Status, $check.Name
        if ($check.Detail) { $line += " - $($check.Detail)" }
        Write-Host $line -ForegroundColor $color
        if ($check.Fix) {
            $label = if ($check.Status -eq 'SKIPPED') { 'Check' } else { 'Fix' }
            Write-Host ("            {0}: {1}" -f $label, $check.Fix) -ForegroundColor Cyan
        }
    }
    $missing = @($script:checks | Where-Object { $_.Status -eq 'MISSING' })
    $warnings = @($script:checks | Where-Object { $_.Status -in @('WARNING', 'UNKNOWN') })
    $manual = @($script:checks | Where-Object { $_.Status -eq 'SKIPPED' })
    Write-Host ""
    Write-Host ("  {0} missing, {1} warning(s), {2} ok, {3} skipped" -f $missing.Count, $warnings.Count, @($script:checks | Where-Object Status -eq 'OK').Count, $manual.Count) -ForegroundColor $(if ($missing.Count -gt 0) { 'Red' } elseif ($warnings.Count -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "##################################################################" -ForegroundColor Magenta
    Write-Host ""
    return $missing.Count
}

# Runs one check. A lookup that throws (access denied, throttling, a PnP/CSOM error)
# becomes an UNKNOWN item under the check's name - one broken lookup must never take the
# rest of the checklist with it.
function RunCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Check
    )
    try {
        & $Check
    }
    catch {
        RecordCheck -Name $Name -Status UNKNOWN -Detail "Could not be checked ($(FirstLine $_.Exception.Message))"
    }
}

# First line only - a CSOM/ARM error can run for paragraphs and would wreck the layout
function FirstLine([string]$Message) {
    return ("$Message".Trim() -split "`r?`n")[0]
}

function IsValidParam {
    [OutputType([bool])]
    param([Parameter(Mandatory = $true)][AllowNull()]$param)
    return $null -ne $param -and -not([string]::IsNullOrEmpty($param.Value)) -and ($param.Value -ne '<<value>>')
}

function FormatTime($Value) {
    try { return ([datetime]$Value).ToLocalTime().ToString('yyyy-MM-dd HH:mm') } catch { return "$Value" }
}

# ---------------------------------------------------------------------------
# Azure CLI helpers. stdout and stderr are kept apart so a failure can be classified:
# NotFound means the resource is not there (MISSING), anything else means the lookup did
# not answer the question (UNKNOWN). Reading a missing resource as "unknown" only costs
# a re-run; reading a 403 as "missing" sends someone off to redeploy for nothing.
# ---------------------------------------------------------------------------
# az prints Graph/ARM errors as 'ERROR: Forbidden({"error":{...}})' - one line of JSON
# that can run for a screen. Keep the status and the error message, capped.
function ShortAzError([string]$Stderr) {
    $text = (FirstLine $Stderr) -replace '^ERROR:\s*', ''
    if ($text -match '^(\w+)\((\{.*\})\)$') {
        try {
            $message = "$((($Matches[2] | ConvertFrom-Json -ErrorAction Stop).error).message)"
            if ($message) { $text = "$($Matches[1]): $message" }
        }
        catch {}
    }
    if ($text.Length -gt 200) { $text = $text.Substring(0, 197) + '...' }
    return $text
}

function InvokeAz {
    $output = & az @args --only-show-errors 2>&1
    $exitCode = $LASTEXITCODE
    $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" }) -join "`n"
    $stderr = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" }) -join "`n"
    $failed = $exitCode -ne 0
    return [pscustomobject]@{
        Ok       = -not $failed
        Output   = $stdout.Trim()
        Error    = if ($failed) { $(if ($stderr) { ShortAzError $stderr } else { "az exited with code $exitCode" }) } else { $null }
        NotFound = $failed -and ($stderr -match '(?i)ResourceNotFound|ResourceGroupNotFound|Request_ResourceNotFound|Not Found|\(404\)|could not be found|was not found|does not exist')
    }
}

# GET against ARM ($Path starts with /subscriptions/...) or Graph ($Path relative to
# v1.0), parsed. Query parameters other than api-version go through --url-parameters:
# az is a .cmd on Windows, and an unquoted '&' in the url would end the command there.
function AzGet {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [string[]]$UrlParameters = @()
    )
    $azArgs = @('rest', '--method', 'get', '--url', $Url)
    if ($UrlParameters.Count -gt 0) { $azArgs += @('--url-parameters') + $UrlParameters }
    $result = InvokeAz @azArgs
    $data = $null
    if ($result.Ok -and $result.Output) {
        try { $data = $result.Output | ConvertFrom-Json -ErrorAction Stop }
        catch { $result.Ok = $false; $result.Error = "unreadable response ($(FirstLine $_.Exception.Message))" }
    }
    $result | Add-Member -NotePropertyName Data -NotePropertyValue $data
    return $result
}

function ArmGet([string]$Path, [string]$ApiVersion, [string[]]$UrlParameters = @()) {
    return AzGet -Url "https://management.azure.com$Path`?api-version=$ApiVersion" -UrlParameters $UrlParameters
}

function GraphGet([string]$Path, [string[]]$UrlParameters = @()) {
    return AzGet -Url "https://graph.microsoft.com/v1.0/$Path" -UrlParameters $UrlParameters
}

# ---------------------------------------------------------------------------
# SharePoint checks
# ---------------------------------------------------------------------------
function CheckSpoAdminAccess {
    $name = "Sign-in: SharePoint admin"
    if ($script:pnpConnectError) {
        RecordCheck -Name $name -Status MISSING -Detail "PnP sign-in to $adminSiteUrl failed ($script:pnpConnectError)" -Fix "Check pnpAppId in $parametersFileName and that the PnP app exists in this tenant, then re-run."
        return
    }
    if ($script:spoAdminAccessError) {
        RecordCheck -Name $name -Status MISSING -Detail "Signed in as $script:pnpIdentity, but the tenant admin API returned: $script:spoAdminAccessError - the SharePoint checks below cannot answer" -Fix "That account must be a SharePoint Administrator in THIS tenant. PnP.PowerShell caches the account on disk, so to sign in as another: Remove-Item `"`$env:LOCALAPPDATA\.m365pnppowershell\pnp.msal.cache`" -Force, then re-run."
        return
    }
    RecordCheck -Name $name -Status OK -Detail "$script:pnpIdentity"
}

# Same classification as deploy.ps1's GetSiteExistenceState: only an unambiguous
# not-found means the site is missing.
function CheckRequestsSite {
    $name = "SharePoint: requests site"
    $script:siteState = 'Unknown'
    try {
        $site = Get-PnPTenantSite -Url $requestsSiteUrl -ErrorAction Stop
        $script:siteState = if ($null -ne $site) { 'Exists' } else { 'NotFound' }
    }
    catch {
        $message = "$($_.Exception.Message)"
        if ($message -match '(?i)file not found|cannot get site|could not be found|does not exist|404') {
            $script:siteState = 'NotFound'
        }
        else {
            RecordCheck -Name $name -Status UNKNOWN -Detail "Could not look up $requestsSiteUrl ($(FirstLine $message))"
            return
        }
    }
    if ($script:siteState -eq 'NotFound') {
        RecordCheck -Name $name -Status MISSING -Detail "$requestsSiteUrl does not exist" -Fix "Check spoTenantName, managedPath and requestsSiteAlias in $parametersFileName - or run deploy.ps1 to create the site."
        return
    }
    RecordCheck -Name $name -Status OK -Detail "$requestsSiteUrl"
}

function ConnectRequestsSite {
    $script:siteConnection = $null
    $script:siteConnectError = $null
    if ($script:siteState -eq 'NotFound') { return }
    try {
        $script:siteConnection = Connect-PnPOnline -Url $requestsSiteUrl -ClientId $parameters.pnpAppId.Value -Interactive -ReturnConnection -ErrorAction Stop
    }
    catch {
        $script:siteConnectError = FirstLine $_.Exception.Message
    }
}

# Records SKIPPED/UNKNOWN for a check that needs the requests site, and returns $false
# when there is no connection to run it on.
function RequireSiteConnection([string]$Name) {
    if ($script:siteState -eq 'NotFound') {
        RecordCheck -Name $Name -Status SKIPPED -Detail "The requests site does not exist"
        return $false
    }
    if ($null -eq $script:siteConnection) {
        RecordCheck -Name $Name -Status UNKNOWN -Detail "Could not connect to $requestsSiteUrl ($script:siteConnectError)"
        return $false
    }
    return $true
}

function CheckLists {
    $name = "SharePoint: lists"
    if (-not (RequireSiteConnection $name)) { return }
    $titles = @(Get-PnPList -Connection $script:siteConnection -ErrorAction Stop | ForEach-Object { "$($_.Title)" })
    $missing = @($expectedLists | Where-Object { $titles -notcontains $_ })
    if ($missing.Count -gt 0) {
        RecordCheck -Name $name -Status MISSING -Detail "Missing: $($missing -join ', ')" -Fix "Run deploy.ps1 and answer y to re-apply the PnP provisioning template - existing list content is kept (the DataRows use UpdateBehavior=Skip)."
        return
    }
    RecordCheck -Name $name -Status OK -Detail "All $($expectedLists.Count) lists"
}

# CAML for a single settings row by Title, as deploy.ps1's SettingQuery
function SettingQuery([string]$Title) {
    return "<View><Query><Where><Eq><FieldRef Name='Title'/><Value Type='Text'>$Title</Value></Eq></Where></Query><RowLimit>1</RowLimit></View>"
}

function ReadSetting([string]$Title) {
    $item = @(Get-PnPListItem -List $requestSettingsListName -Query (SettingQuery $Title) -Connection $script:siteConnection -ErrorAction Stop | Where-Object { $null -ne $_ })
    if ($item.Count -eq 0) { return $null }
    $value = "$($item[0].FieldValues['Value'])".Trim()
    if ([string]::IsNullOrEmpty($value)) { return $null }
    return $value
}

# The version stamp is written by deploy.ps1's StampInstalledVersion - and only when no
# component FAILED, so a missing stamp also says the last run did not finish cleanly.
function CheckInstalledVersion {
    $name = "SharePoint: installed version"
    if (-not (RequireSiteConnection $name)) { return }
    $installed = ReadSetting $installedVersionSettingName
    $date = ReadSetting $installedDateSettingName
    $repoText = if ($repoVersion) { $repoVersion } else { "unknown (VERSION in the repo root is missing or malformed)" }

    if (-not $installed) {
        if ($SharePointOnly) {
            RecordCheck -Name $name -Status SKIPPED -Detail "Not stamped yet - expected after deploy.ps1 -SharePointOnly; the full run stamps it"
            return
        }
        RecordCheck -Name $name -Status WARNING -Detail "No $installedVersionSettingName row in '$requestSettingsListName' - deploy.ps1 only stamps the version when no component failed, so the last run did not complete cleanly (repo: $repoText)" -Fix "Look for FAILED in the last DEPLOYMENT SUMMARY, fix it and re-run deploy.ps1 (with -Upgrade on an existing installation)."
        return
    }
    $dateText = if ($date) { ", installed $(FormatTime $date)" } else { ", no $installedDateSettingName row" }
    if ($repoVersion -and $installed -ne $repoVersion) {
        RecordCheck -Name $name -Status WARNING -Detail "$installed$dateText - this checkout is $repoVersion" -Fix "Upgrade with deploy.ps1 -Upgrade (see Upgrade.md) - or, if the environment is meant to stay on $installed, run this script from a checkout of that version."
        return
    }
    RecordCheck -Name $name -Status OK -Detail "$installed$dateText"
}

# The app catalog connection serves the registry and the SPFx checks. Resolved on the
# -admin connection, as deploy.ps1 does.
function ConnectAppCatalog {
    $script:appCatalogUrl = $null
    $script:appCatalogConnection = $null
    $script:appCatalogError = $null
    try {
        $script:appCatalogUrl = Get-PnPTenantAppCatalogUrl -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($script:appCatalogUrl)) {
            $script:appCatalogError = "no tenant app catalog exists"
            return
        }
        $script:appCatalogConnection = Connect-PnPOnline -Url $script:appCatalogUrl -ClientId $parameters.pnpAppId.Value -Interactive -ReturnConnection -ErrorAction Stop
    }
    catch {
        $script:appCatalogError = FirstLine $_.Exception.Message
    }
}

# The web parts and the Teams app find the site through the tenant storage entity
# bp_ProvisionUrls: a plain URL or a JSON array of {title, url}, absolute or
# server-relative, first entry = the tenant default (see deploy.ps1's
# RegisterProvisionInstance). Reading needs no NoScript change - only writing does.
function CheckRegistry {
    $name = "SharePoint: registered in $registryKey"
    $fix = "Re-run deploy.ps1 (it registers the site in every mode, also -Upgrade and -SharePointOnly), or set it by hand - see 'Merknad: Tenant-registeret bp_ProvisionUrls' in Configuration-guide.md."
    if ($null -eq $script:appCatalogConnection) {
        $status = if ($script:appCatalogError -eq "no tenant app catalog exists") { 'MISSING' } else { 'UNKNOWN' }
        RecordCheck -Name $name -Status $status -Detail "Could not read the tenant app catalog ($script:appCatalogError)"
        return
    }
    $raw = "$((Get-PnPStorageEntity -Key $registryKey -Connection $script:appCatalogConnection -ErrorAction Stop).Value)".Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        RecordCheck -Name $name -Status MISSING -Detail "The storage entity is not set - the web parts and the Teams app cannot find the site" -Fix $fix
        return
    }

    $instances = @()
    if ($raw.StartsWith('[')) {
        try { $instances = @($raw | ConvertFrom-Json -ErrorAction Stop) }
        catch {
            RecordCheck -Name $name -Status WARNING -Detail "The value is not valid JSON ($(FirstLine $_.Exception.Message)): $raw" -Fix "Correct it by hand - see 'Merknad: Tenant-registeret bp_ProvisionUrls' in Configuration-guide.md."
            return
        }
    }
    else {
        $instances = @([pscustomobject]@{ title = 'Bestillingsportalen'; url = $raw })
    }

    # Compare server-relative paths: the registry may hold either form
    $normalize = {
        param($u)
        $u = "$u".Trim()
        if ($u -match '^https?://') { try { $u = ([uri]$u).AbsolutePath } catch {} }
        return $u.TrimEnd('/').ToLowerInvariant()
    }
    $target = & $normalize $requestsSiteUrl
    $index = -1
    for ($i = 0; $i -lt $instances.Count; $i++) {
        if ((& $normalize $instances[$i].url) -eq $target) { $index = $i; break }
    }
    if ($index -lt 0) {
        RecordCheck -Name $name -Status MISSING -Detail "$requestsSiteUrl is not among the $($instances.Count) registered instance(s) ($(($instances.url) -join ', '))" -Fix $fix
        return
    }
    $position = if ($index -eq 0) { "the tenant default" } else { "entry $($index + 1) of $($instances.Count) - the default is '$($instances[0].title)'" }
    RecordCheck -Name $name -Status OK -Detail "'$($instances[$index].title)' ($position)"
}

function ResolveServiceAccount {
    $script:saObjectId = $null
    $script:saError = $null
    if (-not (IsValidParam $parameters.serviceAccountUPN)) { return }
    if (-not $script:cliSignedIn) { $script:saError = "the Azure CLI is not signed in"; return }
    $result = InvokeAz ad user show --id $parameters.serviceAccountUPN.Value --query id --output tsv
    if ($result.Ok -and $result.Output) { $script:saObjectId = $result.Output; return }
    $script:saError = if ($result.NotFound) { "NOTFOUND" } else { $result.Error }
}

# Records the outcome when the service account cannot be checked at all, and returns
# $false then.
function RequireServiceAccount([string]$Name) {
    if (-not (IsValidParam $parameters.serviceAccountUPN)) {
        if ($SharePointOnly) {
            RecordCheck -Name $Name -Status SKIPPED -Detail "serviceAccountUPN is empty - expected before the full run, which gives the account access"
        }
        else {
            RecordCheck -Name $Name -Status MISSING -Detail "serviceAccountUPN is empty in $parametersFileName" -Fix "Set serviceAccountUPN and run deploy.ps1 - it gives the account access to the site."
        }
        return $false
    }
    if ($script:saError -eq "NOTFOUND") {
        RecordCheck -Name $Name -Status MISSING -Detail "$($parameters.serviceAccountUPN.Value) was not found in the tenant" -Fix "Create the service account (see Deployment-guide.md), or correct serviceAccountUPN in $parametersFileName."
        return $false
    }
    if ($script:saError) {
        RecordCheck -Name $Name -Status UNKNOWN -Detail "Could not look up $($parameters.serviceAccountUPN.Value) ($script:saError)"
        return $false
    }
    return $true
}

# The approval flow and the Teams welcome message run as the service account and need
# it as owner AND member of the site's Microsoft 365 group - deploy.ps1's
# GrantServiceAccountAccess sets it up.
function CheckServiceAccountGroup {
    $name = "SharePoint: service account in the site's Microsoft 365 group"
    if (-not (RequireServiceAccount $name)) { return }
    if (-not (RequireSiteConnection $name)) { return }
    $upn = $parameters.serviceAccountUPN.Value

    $groupId = "$((Get-PnPSite -Includes GroupId -Connection $script:siteConnection -ErrorAction Stop).GroupId)"
    if ([string]::IsNullOrWhiteSpace($groupId) -or $groupId -eq [guid]::Empty.ToString()) {
        RecordCheck -Name $name -Status MISSING -Detail "The site is not connected to a Microsoft 365 group" -Fix "The requests site must be a group site - recreate it with deploy.ps1."
        return
    }

    $owners = GraphGet "groups/$groupId/owners" @('$select=id')
    if (-not $owners.Ok) {
        RecordCheck -Name $name -Status UNKNOWN -Detail "Could not read the owners of group $groupId ($($owners.Error))"
        return
    }
    $isOwner = @($owners.Data.value.id) -contains $script:saObjectId
    # 'az ad group member check' is a read: Graph's checkMemberObjects, sent as a POST
    $member = InvokeAz ad group member check --group $groupId --member-id $script:saObjectId --query value --output tsv
    if (-not $member.Ok) {
        RecordCheck -Name $name -Status UNKNOWN -Detail "Owner: $(if ($isOwner) { 'yes' } else { 'no' }); could not check membership ($($member.Error))"
        return
    }
    $isMember = $member.Output -eq 'true'

    $lacking = @()
    if (-not $isOwner) { $lacking += 'owner' }
    if (-not $isMember) { $lacking += 'member' }
    if ($lacking.Count -gt 0) {
        RecordCheck -Name $name -Status MISSING -Detail "$upn is not $($lacking -join ' or ') of group $groupId - the approval flow and the Teams welcome message run as this account" -Fix "Re-run deploy.ps1 and answer n to re-applying the template (GrantServiceAccountAccess adds it), or add $upn as OWNER and MEMBER of the group in the Microsoft 365 admin center."
        return
    }
    RecordCheck -Name $name -Status OK -Detail "$upn is owner and member"
}

function CheckServiceAccountSiteAdmin {
    $name = "SharePoint: service account is site collection admin"
    if (-not (IsValidParam $parameters.serviceAccountUPN)) {
        # Same verdict as the group check - RequireServiceAccount records it
        RequireServiceAccount $name | Out-Null
        return
    }
    if (-not (RequireSiteConnection $name)) { return }
    $upn = $parameters.serviceAccountUPN.Value
    # LoginName is claims-encoded (i:0#.f|membership|user@tenant.com) - the UPN is the
    # last segment
    $admins = @(Get-PnPSiteCollectionAdmin -Connection $script:siteConnection -ErrorAction Stop | ForEach-Object { ("$($_.LoginName)" -split '\|')[-1] })
    if ($admins -notcontains $upn) {
        RecordCheck -Name $name -Status MISSING -Detail "$upn is not among the site collection admins" -Fix "Re-run deploy.ps1 and answer n to re-applying the template (GrantServiceAccountAccess adds it), or add $upn as site collection admin on $requestsSiteUrl in the SharePoint admin center."
        return
    }
    RecordCheck -Name $name -Status OK -Detail "$upn"
}

# ---------------------------------------------------------------------------
# SPFx and Teams app
# ---------------------------------------------------------------------------
function GetSpfxSolutions {
    return @(Get-ChildItem -Path $spfxRoot -Directory -ErrorAction SilentlyContinue | Where-Object {
            Test-Path (Join-Path $_.FullName "config/package-solution.json")
        })
}

function CheckSpfxPackages {
    $solutions = GetSpfxSolutions
    if ($solutions.Count -eq 0) {
        RecordCheck -Name "SPFx packages" -Status UNKNOWN -Detail "No SPFx solutions found under $spfxRoot - run the script from the repository"
        return
    }
    $apps = $null
    $appsError = $null
    if ($null -eq $script:appCatalogConnection) {
        $appsError = "could not read the tenant app catalog ($script:appCatalogError)"
    }
    else {
        try { $apps = @(Get-PnPApp -Connection $script:appCatalogConnection -ErrorAction Stop) }
        catch { $appsError = "could not list the apps in the tenant app catalog ($(FirstLine $_.Exception.Message))" }
    }

    foreach ($solution in $solutions) {
        RunCheck "SPFx: $($solution.Name)" {
            $name = "SPFx: $($solution.Name)"
            $package = (Get-Content (Join-Path $solution.FullName "config/package-solution.json") -Raw | ConvertFrom-Json).solution
            if ($appsError) {
                $status = if ($script:appCatalogError -eq "no tenant app catalog exists") { 'MISSING' } else { 'UNKNOWN' }
                RecordCheck -Name $name -Status $status -Detail "'$($package.name)' $($package.version): $appsError"
                return
            }
            # ProductId is the solution id from package-solution.json. Id is the app catalog
            # item's own id, which only matches by accident.
            $app = $apps | Where-Object { "$($_.ProductId)" -eq "$($package.id)" -or "$($_.Id)" -eq "$($package.id)" } | Select-Object -First 1
            $fix = "Run deploy.ps1 -Upgrade (or -SkipSPFxBuild to publish an already built package) - or upload the .sppkg to $script:appCatalogUrl and deploy it."
            if ($null -eq $app) {
                RecordCheck -Name $name -Status MISSING -Detail "'$($package.name)' ($($package.id)) is not in the tenant app catalog" -Fix $fix
                return
            }
            if (-not $app.Deployed) {
                RecordCheck -Name $name -Status MISSING -Detail "'$($app.Title)' $($app.AppCatalogVersion) is uploaded but not deployed" -Fix $fix
                return
            }
            if ("$($app.AppCatalogVersion)" -ne "$($package.version)") {
                RecordCheck -Name $name -Status WARNING -Detail "Version $($app.AppCatalogVersion) in the app catalog, $($package.version) in this checkout" -Fix "$fix If the environment is meant to stay on $($app.AppCatalogVersion), run this script from a checkout of that version."
                return
            }
            RecordCheck -Name $name -Status OK -Detail "'$($app.Title)' $($app.AppCatalogVersion), deployed"
        }
    }
}

# Reading the Teams app catalog needs AppCatalog.Read.All (or Directory.Read.All) - the
# PnP app only has it where AppCatalog.ReadWrite.All was granted for publishing, and the
# Azure CLI's token rarely does. Tried with both; a refusal is a WARNING saying it could
# not be checked, never a MISSING: many tenants upload the app by hand, or skip it.
function CheckTeamsApp {
    foreach ($solution in (GetSpfxSolutions)) {
        $manifestPath = Join-Path $solution.FullName "teams/manifest.json"
        if (-not (Test-Path $manifestPath)) { continue }
        RunCheck "Teams app: $($solution.Name)" {
            $name = "Teams app: $($solution.Name)"
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            # The Teams app version follows the solution version (first three parts), as
            # deploy.ps1's PublishTeamsApp stamps it
            $solutionVersion = (Get-Content (Join-Path $solution.FullName "config/package-solution.json") -Raw | ConvertFrom-Json).solution.version
            $expectedVersion = ($solutionVersion -split '\.')[0..2] -join '.'
            $filter = "externalId eq '$($manifest.id)'"

            $apps = $null
            $reasons = @()
            try {
                $headers = @{ Authorization = "Bearer $(Get-PnPAccessToken -ErrorAction Stop)" }
                $uri = "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps?`$filter=$([uri]::EscapeDataString($filter))&`$expand=appDefinitions"
                $apps = @((Invoke-RestMethod -Method Get -Headers $headers -Uri $uri -ErrorAction Stop).value)
            }
            catch {
                $reasons += "PnP app: $(FirstLine $_.Exception.Message)"
            }
            if ($null -eq $apps -and $script:cliSignedIn) {
                $result = GraphGet "appCatalogs/teamsApps" @("`$filter=$filter", '$expand=appDefinitions')
                if ($result.Ok) { $apps = @($result.Data.value) } else { $reasons += "Azure CLI: $($result.Error)" }
            }
            $manualCheck = "Teams admin center -> Teams apps -> Manage apps -> search for '$($manifest.name.short)': it should be there, version $expectedVersion, allowed."
            if ($null -eq $apps) {
                # The usual case: neither token carries a scope that may read the catalog
                $why = if (@($reasons | Where-Object { $_ -notmatch '(?i)403|Forbidden' }).Count -eq 0) { "neither the PnP app nor the Azure CLI has AppCatalog.Read.All - normal, nothing to fix" } else { $reasons -join '; ' }
                RecordCheck -Name $name -Status WARNING -Detail "Could not be checked - the Teams app catalog cannot be read with these sign-ins ($why)" -Fix "Check by hand: $manualCheck"
                return
            }
            $app = $apps | Select-Object -First 1
            if ($null -eq $app) {
                RecordCheck -Name $name -Status WARNING -Detail "'$($manifest.name.short)' is not in the Teams app catalog" -Fix "Upload sharepoint/solution/bestillingsportalen-teams-app.zip in the Teams admin center (Manage apps -> Upload new app) - see 'Teams-appen' in Deployment-guide.md. Ignore this if the organisation does not use the Teams app."
                return
            }
            $versions = @($app.appDefinitions.version)
            if ($versions -notcontains $expectedVersion) {
                RecordCheck -Name $name -Status WARNING -Detail "'$($app.displayName)' is in the Teams app catalog as $($versions -join ', '), this checkout is $expectedVersion" -Fix "Run deploy.ps1 -Upgrade - it publishes the new version when the PnP app has AppCatalog.ReadWrite.All, and otherwise builds the zip to upload on the app in the Teams admin center ('Upload file')."
                return
            }
            RecordCheck -Name $name -Status OK -Detail "'$($app.displayName)' $expectedVersion"
        }
    }
}

# ---------------------------------------------------------------------------
# Azure checks
# ---------------------------------------------------------------------------
function CheckAutomationAccount {
    $name = "Automation: account $automationAccountName"
    $script:automationPrincipalId = $null
    $script:automationFound = $false
    $result = ArmGet "$rgPath/providers/Microsoft.Automation/automationAccounts/$automationAccountName" "2023-11-01"
    if ($result.NotFound) {
        RecordCheck -Name $name -Status MISSING -Detail "Not found in resource group $resourceGroupName" -Fix "Run deploy.ps1 without -SharePointOnly - azureresources.bicep creates it."
        return
    }
    if (-not $result.Ok) {
        RecordCheck -Name $name -Status UNKNOWN -Detail "Could not read it ($($result.Error))"
        return
    }
    $script:automationFound = $true
    $script:automationPrincipalId = "$($result.Data.identity.principalId)"
    if ([string]::IsNullOrWhiteSpace($script:automationPrincipalId)) {
        $script:automationPrincipalId = $null
        RecordCheck -Name $name -Status MISSING -Detail "Exists, but has no system-assigned managed identity" -Fix "Run deploy.ps1 - azureresources.bicep enables the identity."
        return
    }
    RecordCheck -Name $name -Status OK -Detail "System-assigned identity $script:automationPrincipalId"
}

function CheckRuntimeEnvironment {
    $name = "Automation: runtime environment $runtimeEnvironmentName"
    if (-not $script:automationFound) {
        RecordCheck -Name $name -Status SKIPPED -Detail "The automation account could not be read"
        return
    }
    $result = ArmGet "$automationPath/runtimeEnvironments/$runtimeEnvironmentName" "2024-10-23"
    if ($result.NotFound) {
        RecordCheck -Name $name -Status MISSING -Detail "Not found - the runbooks need PowerShell 7.4 with PnP.PowerShell 3.x" -Fix "Run deploy.ps1 (-Upgrade is enough) - runbooks.bicep creates it."
        return
    }
    if (-not $result.Ok) {
        RecordCheck -Name $name -Status UNKNOWN -Detail "Could not read it ($($result.Error))"
        return
    }
    $runtime = $result.Data.properties.runtime
    RecordCheck -Name $name -Status OK -Detail "$($runtime.language) $($runtime.version)"
}

# Published, and on the 7.4 runtime environment - the same REST call as deploy.ps1's
# VerifyRunbookRuntimeEnvironment. Note that the portal's default Runbooks blade shows
# 7.2+ runtime environments as 'PowerShell 5.1'; this reads the real value.
function CheckRunbook([string]$Runbook) {
    $name = "Automation: runbook $Runbook"
    if (-not $script:automationFound) {
        RecordCheck -Name $name -Status SKIPPED -Detail "The automation account could not be read"
        return
    }
    $isCustomer = $Runbook -eq $customerRunbook
    $fix = if ($isCustomer) { "Run deploy.ps1 (-Upgrade is enough) - it creates CustomerSpecific with the default no-op content when it is missing." } else { "Run deploy.ps1 (-Upgrade is enough) - it publishes the runbook content from Source/Runbooks/." }

    $result = ArmGet "$automationPath/runbooks/$Runbook" "2024-10-23"
    if ($result.NotFound) {
        RecordCheck -Name $name -Status MISSING -Detail "Not found - the logic apps that call it fail" -Fix $fix
        return
    }
    if (-not $result.Ok) {
        RecordCheck -Name $name -Status UNKNOWN -Detail "Could not read it ($($result.Error))"
        return
    }
    $state = "$($result.Data.properties.state)"
    $runtime = "$($result.Data.properties.runtimeEnvironment)"
    if ([string]::IsNullOrWhiteSpace($runtime)) { $runtime = '(classic runtime)' }

    # New = never published, so there is nothing to run
    if ($state -eq 'New') {
        RecordCheck -Name $name -Status MISSING -Detail "Never published (state New)" -Fix $fix
        return
    }
    if ($runtime -ne $runtimeEnvironmentName) {
        $runtimeFix = "Re-link it under Automation account -> Runtime environments -> $runtimeEnvironmentName."
        if ($isCustomer) {
            # Customer-owned and never overwritten by deploy.ps1, so a WARNING as in
            # VerifyRunbookRuntimeEnvironment
            RecordCheck -Name $name -Status WARNING -Detail "On '$runtime', not '$runtimeEnvironmentName' - customer code using PnP 3.x cmdlets fails there" -Fix $runtimeFix
        }
        else {
            RecordCheck -Name $name -Status MISSING -Detail "On '$runtime', not '$runtimeEnvironmentName' - it fails with 'Connect-PnPOnline is not recognized'" -Fix "$runtimeFix Or delete the runbook and re-run deploy.ps1."
        }
        return
    }
    # Edit = published, with an unpublished draft on top. The published version runs.
    if ($state -eq 'Edit') {
        RecordCheck -Name $name -Status WARNING -Detail "Published, on $runtime, but has an unpublished draft - the published version is what runs" -Fix "Publish or discard the draft in the portal. $(if (-not $isCustomer) { 'deploy.ps1 overwrites portal edits on the next run - customisations belong in the repo.' })"
        return
    }
    RecordCheck -Name $name -Status OK -Detail "$state, $runtime"
}

function CheckUami {
    $name = "Managed identity: $uamiName"
    $script:uamiPrincipalId = $null
    $result = ArmGet "$rgPath/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$uamiName" "2023-01-31"
    if ($result.NotFound) {
        RecordCheck -Name $name -Status MISSING -Detail "Not found in resource group $resourceGroupName - the logic apps authenticate with it" -Fix "Run deploy.ps1 without -Upgrade - azureresources.bicep creates it. Check uamiName in $parametersFileName if it was renamed."
        return
    }
    if (-not $result.Ok) {
        RecordCheck -Name $name -Status UNKNOWN -Detail "Could not read it ($($result.Error))"
        return
    }
    $script:uamiPrincipalId = "$($result.Data.properties.principalId)"
    RecordCheck -Name $name -Status OK -Detail "Principal $script:uamiPrincipalId"
}

# The expected role sets, read from AssignPermissionsToManagedIdentity.ps1 so they live
# in one place: the script's $automationGraphRoles / $uamiGraphRoles. That script gives
# BOTH identities SharePoint Sites.FullControl.All (IncludeSpo = $true for each target) -
# that one is listed here; keep it in sync if the script changes.
function GetExpectedAppRoles {
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($assignScriptPath, [ref]$null, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw "AssignPermissionsToManagedIdentity.ps1 does not parse: $($parseErrors[0].Message)" }

    $readRoles = {
        param($variableName)
        $assignment = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $node.Left.VariablePath.UserPath -eq $variableName
            }, $true) | Select-Object -First 1
        if ($null -eq $assignment) { throw "`$$variableName was not found in AssignPermissionsToManagedIdentity.ps1" }
        $roles = @($assignment.Right.FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true).Value)
        if ($roles.Count -eq 0) { throw "`$$variableName in AssignPermissionsToManagedIdentity.ps1 holds no roles" }
        return $roles
    }

    $spoRoles = @('Sites.FullControl.All')
    return @{
        Automation = @{ Graph = @(& $readRoles 'automationGraphRoles'); SharePoint = $spoRoles }
        Uami       = @{ Graph = @(& $readRoles 'uamiGraphRoles'); SharePoint = $spoRoles }
    }
}

# Microsoft Graph and SharePoint Online service principals in the tenant, with their app
# roles, to translate an assignment's appRoleId into a role name.
function GetResourceServicePrincipals {
    $resources = @{}
    foreach ($entry in @(@{ Key = 'Graph'; AppId = $graphAppId }, @{ Key = 'SharePoint'; AppId = $spoAppId })) {
        $result = GraphGet "servicePrincipals" @("`$filter=appId eq '$($entry.AppId)'", '$select=id,displayName,appRoles')
        if (-not $result.Ok) { throw "could not read the $($entry.Key) service principal ($($result.Error))" }
        $sp = @($result.Data.value) | Select-Object -First 1
        if ($null -eq $sp) { throw "the $($entry.Key) service principal ($($entry.AppId)) was not found in the tenant" }
        $roleNames = @{}
        foreach ($role in @($sp.appRoles)) { $roleNames["$($role.id)"] = "$($role.value)" }
        $resources[$entry.Key] = @{ Id = "$($sp.id)"; RoleNames = $roleNames }
    }
    return $resources
}

# Exactly the documented role set: missing roles are MISSING (the logic apps/runbooks get
# 401/403), extra Graph/SharePoint roles a WARNING (more than the solution needs).
# Roles assigned less than ~24 hours ago are pointed out, because the identity's cached
# tokens may not carry them yet.
function CheckAppRoles {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [AllowEmptyString()][string]$PrincipalId,
        [Parameter(Mandatory = $true)][string]$ParameterName,
        [hashtable]$Expected
    )
    $name = "App roles: $Label"
    if ([string]::IsNullOrWhiteSpace($PrincipalId)) {
        RecordCheck -Name $name -Status SKIPPED -Detail "The identity could not be resolved - see the item above"
        return
    }
    if ($script:appRoleSetupError) {
        RecordCheck -Name $name -Status UNKNOWN -Detail $script:appRoleSetupError
        return
    }
    $result = GraphGet "servicePrincipals/$PrincipalId/appRoleAssignments"
    if (-not $result.Ok) {
        $status = if ($result.NotFound) { 'MISSING' } else { 'UNKNOWN' }
        RecordCheck -Name $name -Status $status -Detail "Could not read the assignments of $PrincipalId ($($result.Error))"
        return
    }

    $assigned = @{ Graph = @(); SharePoint = @() }
    $recent = @()
    foreach ($assignment in @($result.Data.value)) {
        foreach ($key in @('Graph', 'SharePoint')) {
            $resource = $script:resourceSps[$key]
            if ("$($assignment.resourceId)" -ne $resource.Id) { continue }
            $roleName = $resource.RoleNames["$($assignment.appRoleId)"]
            if (-not $roleName) { $roleName = "$($assignment.appRoleId)" }
            $assigned[$key] += $roleName
            if ($assignment.createdDateTime) {
                try {
                    $created = ([datetime]$assignment.createdDateTime).ToUniversalTime()
                    if (([datetime]::UtcNow - $created).TotalHours -lt $tokenCacheHours) {
                        $recent += $roleName
                        if ($null -eq $script:latestAppRoleAssignment -or $created -gt $script:latestAppRoleAssignment) { $script:latestAppRoleAssignment = $created }
                    }
                }
                catch {}
            }
        }
    }

    $missing = @()
    $extra = @()
    foreach ($key in @('Graph', 'SharePoint')) {
        $missing += @($Expected[$key] | Where-Object { $assigned[$key] -notcontains $_ } | ForEach-Object { "$key $_" })
        $extra += @($assigned[$key] | Where-Object { $Expected[$key] -notcontains $_ } | ForEach-Object { "$key $_" })
    }
    $expectedCount = $Expected.Graph.Count + $Expected.SharePoint.Count

    if ($missing.Count -gt 0) {
        # The logic apps authenticate with the user-assigned identity - CheckLogicApps
        # points its failed runs here
        if ($ParameterName -eq 'UamiId') { $script:uamiRolesMissing = $true }
        $command = "./AssignPermissionsToManagedIdentity.ps1 -TenantId $($parameters.tenantId.Value) -$ParameterName $PrincipalId"
        RecordCheck -Name $name -Status MISSING -Detail "$($expectedCount - $missing.Count) of $expectedCount roles - the solution gets 401/403 until the rest are assigned" -Fix "Missing: $($missing -join ', '). Have a Global Administrator run: $command - tokens are cached for up to ~$tokenCacheHours h afterwards."
        return
    }
    if ($extra.Count -gt 0) {
        RecordCheck -Name $name -Status WARNING -Detail "All $expectedCount roles, plus roles the solution does not assign: $($extra -join ', ')" -Fix "Remove the extra roles if nothing else uses this identity (least privilege) - the solution's set is documented in Data-access-security.md."
        return
    }
    if ($recent.Count -gt 0) {
        RecordCheck -Name $name -Status WARNING -Detail "All $expectedCount roles, but $($recent -join ', ') assigned less than $tokenCacheHours h ago (latest $(FormatTime $script:latestAppRoleAssignment))" -Fix "Nothing to fix - managed identity tokens are cached for up to ~$tokenCacheHours h, so sporadic 401/403 until $(FormatTime $script:latestAppRoleAssignment.AddHours($tokenCacheHours)) are expected. Do not troubleshoot them before then."
        return
    }
    RecordCheck -Name $name -Status OK -Detail "Exactly the $expectedCount roles AssignPermissionsToManagedIdentity.ps1 assigns"
}

# Status as Authorize-ApiConnections.ps1's Get-ConnectionStatus reads it
function CheckApiConnection([string]$Connection) {
    $name = "API connection: $Connection"
    $isAutomation = $Connection -eq $automationConnection
    $result = ArmGet "$rgPath/providers/Microsoft.Web/connections/$Connection" "2016-06-01"
    if ($result.NotFound) {
        RecordCheck -Name $name -Status MISSING -Detail "Not found in resource group $resourceGroupName" -Fix "Run deploy.ps1 without -Upgrade (which skips the API connections) - apiconnections.json creates it."
        return
    }
    if (-not $result.Ok) {
        RecordCheck -Name $name -Status UNKNOWN -Detail "Could not read it ($($result.Error))"
        return
    }
    $statusEntry = @($result.Data.properties.statuses) | Select-Object -First 1
    $status = "$($statusEntry.status)"
    $okStatuses = if ($isAutomation) { @('Connected', 'Ready') } else { @('Connected') }
    if ($status -in $okStatuses) {
        RecordCheck -Name $name -Status OK -Detail $status
        return
    }
    $reason = if ($statusEntry.error.message) { " ($(FirstLine $statusEntry.error.message))" } else { "" }
    if ($isAutomation) {
        RecordCheck -Name $name -Status MISSING -Detail "Status '$status'$reason - the runbook calls go out without an Authorization header" -Fix "Run deploy.ps1 without -Upgrade - it recreates this managed identity connection when it is not Ready (no credentials or consent involved)."
        return
    }
    RecordCheck -Name $name -Status MISSING -Detail "Status '$(if ($status) { $status } else { 'none' })'$reason" -Fix "Run ./Authorize-ApiConnections.ps1 -ResourceGroupName $resourceGroupName -SubscriptionId $subscriptionId and sign in as $($parameters.serviceAccountUPN.Value) - or in the Azure Portal: the connection -> Edit API connection -> Authorize, as the service account, Save."
}

function CheckLogicApps {
    $list = ArmGet "$rgPath/providers/Microsoft.Logic/workflows" "2019-05-01"
    if (-not $list.Ok) {
        $status = if ($list.NotFound) { 'MISSING' } else { 'UNKNOWN' }
        RecordCheck -Name "Logic Apps" -Status $status -Detail "Could not list the logic apps in $resourceGroupName ($($list.Error))"
        return
    }
    $workflows = @($list.Data.value)
    $names = @($workflows | ForEach-Object { "$($_.name)" })

    foreach ($expected in $expectedLogicApps) {
        if ($names -notcontains $expected) {
            RecordCheck -Name "Logic App: $expected" -Status MISSING -Detail "Not found in resource group $resourceGroupName" -Fix $(if ($expected -in @('ProcessGuests', 'ProcessProvisionRequest', 'ProcessGuestRequest')) { "Run deploy.ps1 (-Upgrade is enough) - it deploys this logic app." } else { "Run deploy.ps1 without -Upgrade - -Upgrade deploys only ProcessGuests, ProcessProvisionRequest and ProcessGuestRequest." })
        }
    }

    # Every logic app in the resource group, the customer's own included
    foreach ($workflow in ($workflows | Sort-Object { $i = $expectedLogicApps.IndexOf("$($_.name)"); if ($i -lt 0) { [int]::MaxValue } else { $i } }, { "$($_.name)" })) {
        $workflowName = "$($workflow.name)"
        RunCheck "Logic App: $workflowName" {
            $name = "Logic App: $workflowName"
            $state = "$($workflow.properties.state)"
            $runs = ArmGet "$rgPath/providers/Microsoft.Logic/workflows/$workflowName/runs" "2019-05-01" @('$top=1')
            $runText = $null
            $latest = $null
            if ($runs.Ok) {
                $latest = @($runs.Data.value) | Select-Object -First 1
                $runText = if ($latest) { "latest run $($latest.properties.status) $(FormatTime $latest.properties.startTime)" } else { "no runs yet" }
            }
            else {
                $runText = "latest run could not be read ($($runs.Error))"
            }

            if ($state -ne 'Enabled') {
                RecordCheck -Name $name -Status MISSING -Detail "$(if ($state) { $state } else { 'No state' }), $runText" -Fix "Enable it: Azure Portal -> $workflowName -> Overview -> Enable."
                return
            }
            if (-not $runs.Ok) {
                RecordCheck -Name $name -Status UNKNOWN -Detail "Enabled, $runText"
                return
            }
            if ($latest -and "$($latest.properties.status)" -in @('Failed', 'TimedOut', 'Aborted')) {
                $errorText = if ($latest.properties.error.message) { " - $(FirstLine $latest.properties.error.message)" } else { "" }
                $runFix = if ($script:uamiRolesMissing) {
                    "Most likely the missing app roles on $uamiName (see above) - assign them, wait out the ~$tokenCacheHours h token cache and run it again. To confirm, open the run: Azure Portal -> $workflowName -> Run history -> the failed action (401/403)."
                }
                else {
                    "Open the run: Azure Portal -> $workflowName -> Run history, and read the failed action. See Error-handling.md. A 401/403 within ~$tokenCacheHours h of the app role assignment is the token cache, not an error."
                }
                RecordCheck -Name $name -Status WARNING -Detail "Enabled, $runText$errorText" -Fix $runFix
                return
            }
            if (-not $latest -and $workflowName -in $supportLogicApps) {
                RecordCheck -Name $name -Status WARNING -Detail "Enabled, never run - the list it fills stays empty until its weekly schedule" -Fix "Run it once now: Azure Portal -> $workflowName -> Run trigger -> Run (Configuration-guide.md Steg 4)."
                return
            }
            RecordCheck -Name $name -Status OK -Detail "Enabled, $runText"
        }
    }
}

# ---------------------------------------------------------------------------
# -TriggerLogicApps: run the scheduled logic apps and wait for the results
# ---------------------------------------------------------------------------
$terminalRunStates = @('Succeeded', 'Failed', 'Cancelled', 'TimedOut', 'Aborted', 'Skipped')

# Run and trigger times as UTC. ConvertFrom-Json turns ARM's ISO timestamps into
# DateTime (Kind Utc) - but DateTime comparisons ignore Kind, so everything compared
# against [DateTime]::UtcNow goes through here.
function ToUtc($Value) {
    if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
    return ([DateTimeOffset]::Parse("$Value", [Globalization.CultureInfo]::InvariantCulture)).UtcDateTime
}

# The name of the workflow's Recurrence trigger, or $null when it has none - found from
# the definition, so the set follows the templates (and includes a customer's own
# scheduled logic app) instead of a list kept here.
function GetRecurrenceTrigger($Workflow) {
    $definition = $Workflow.properties.definition
    if ($null -eq $definition) {
        $full = ArmGet "$rgPath/providers/Microsoft.Logic/workflows/$($Workflow.name)" "2019-05-01"
        if ($full.Ok) { $definition = $full.Data.properties.definition }
    }
    if ($null -eq $definition -or $null -eq $definition.triggers) { return $null }
    foreach ($trigger in $definition.triggers.PSObject.Properties) {
        if ("$($trigger.Value.type)" -eq 'Recurrence') { return $trigger.Name }
    }
    return $null
}

# The failed action of a run as 'action: code - message', or $null. A scope fails with
# ActionFailed because something inside it failed, so an action with a real error code
# is preferred. Best effort - the run itself is the authority.
function GetFailedActionText([string]$WorkflowName, [string]$RunName) {
    $actions = ArmGet "$rgPath/providers/Microsoft.Logic/workflows/$WorkflowName/runs/$RunName/actions" "2019-05-01"
    if (-not $actions.Ok) { return $null }
    $failed = @($actions.Data.value | Where-Object { "$($_.properties.status)" -eq 'Failed' })
    if ($failed.Count -eq 0) { return $null }
    $pick = $failed | Where-Object { "$($_.properties.code)" -ne 'ActionFailed' } | Select-Object -First 1
    if ($null -eq $pick) { $pick = $failed | Select-Object -First 1 }
    $text = "$($pick.name)"
    if ($pick.properties.code) { $text += ": $($pick.properties.code)" }
    if ($pick.properties.error.message) { $text += " - $(FirstLine $pick.properties.error.message)" }
    if ($text.Length -gt 200) { $text = $text.Substring(0, 197) + '...' }
    return $text
}

function InvokeScheduledLogicApps {
    $list = ArmGet "$rgPath/providers/Microsoft.Logic/workflows" "2019-05-01"
    if (-not $list.Ok) {
        RecordCheck -Name "Logic App runs" -Status UNKNOWN -Detail "Could not list the logic apps in $resourceGroupName ($($list.Error)) - nothing was started"
        return
    }

    $started = @()
    foreach ($workflow in (@($list.Data.value) | Sort-Object { "$($_.name)" })) {
        $workflowName = "$($workflow.name)"
        $triggerName = GetRecurrenceTrigger $workflow
        if (-not $triggerName) { continue }
        $name = "Logic App run: $workflowName"
        $state = "$($workflow.properties.state)"
        if ($state -ne 'Enabled') {
            RecordCheck -Name $name -Status WARNING -Detail "Not started - the logic app is $(if ($state) { $state } else { 'not enabled' })" -Fix "Enable it (Azure Portal -> $workflowName -> Overview -> Enable) and re-run with -TriggerLogicApps."
            continue
        }
        # Taken before the POST: the run's startTime is compared against it to tell the
        # run started here from an earlier one
        $startedAt = [DateTime]::UtcNow
        $post = InvokeAz rest --method post --url "https://management.azure.com$rgPath/providers/Microsoft.Logic/workflows/$workflowName/triggers/$triggerName/run?api-version=2016-06-01"
        if (-not $post.Ok) {
            RecordCheck -Name $name -Status WARNING -Detail "Could not be started ($($post.Error))" -Fix "Starting a run needs Logic App Contributor (or Contributor) on $resourceGroupName. Or run it by hand: Azure Portal -> $workflowName -> Run trigger -> Run."
            continue
        }
        Write-Host "  Started $workflowName" -ForegroundColor Gray
        $started += [pscustomobject]@{ Workflow = $workflowName; Trigger = $triggerName; StartedAt = $startedAt; Run = $null }
    }
    if ($started.Count -eq 0) {
        if (@($script:checks | Where-Object Name -like 'Logic App run: *').Count -eq 0) {
            RecordCheck -Name "Logic App runs" -Status UNKNOWN -Detail "No logic app with a Recurrence trigger found in $resourceGroupName - nothing was started"
        }
        return
    }

    # All started at once, then polled together: the total wait is the slowest run, not
    # the sum. Short sleeps, so Ctrl+C is handled promptly.
    Write-Host "Waiting for $($started.Count) logic app run(s) - up to $LogicAppTimeoutMinutes min. Ctrl+C stops the script; the runs finish in Azure regardless." -ForegroundColor Yellow
    $deadline = [DateTime]::UtcNow.AddMinutes($LogicAppTimeoutMinutes)
    $pending = @($started)
    $lastProgress = $null
    $lastProgressAt = [DateTime]::UtcNow
    while ($pending.Count -gt 0 -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Seconds 10
        foreach ($item in $pending) {
            $runs = ArmGet "$rgPath/providers/Microsoft.Logic/workflows/$($item.Workflow)/runs" "2019-05-01" @('$top=5')
            if (-not $runs.Ok) { continue }
            # The run started here: the newest from this trigger since the POST. A minute of
            # slack for the clock difference between this machine and Azure.
            $run = @($runs.Data.value) | Where-Object {
                "$($_.properties.trigger.name)" -eq $item.Trigger -and $_.properties.startTime -and (ToUtc $_.properties.startTime) -ge $item.StartedAt.AddMinutes(-1)
            } | Select-Object -First 1
            if ($run) { $item.Run = $run }
        }
        $pending = @($pending | Where-Object { $null -eq $_.Run -or "$($_.Run.properties.status)" -notin $terminalRunStates })
        # A line when a run finishes, otherwise one a minute - not one per poll
        $progress = "  $($started.Count - $pending.Count) of $($started.Count) finished - waiting for $(@($pending.Workflow) -join ', ')"
        if ($pending.Count -gt 0 -and ($progress -ne $lastProgress -or ([DateTime]::UtcNow - $lastProgressAt).TotalSeconds -ge 60)) {
            Write-Host $progress -ForegroundColor Gray
            $lastProgress = $progress
            $lastProgressAt = [DateTime]::UtcNow
        }
    }

    foreach ($item in $started) {
        $name = "Logic App run: $($item.Workflow)"
        $historyHint = "Azure Portal -> $($item.Workflow) -> Run history"
        if ($null -eq $item.Run) {
            RecordCheck -Name $name -Status WARNING -Detail "Started, but no run showed up within $LogicAppTimeoutMinutes min" -Fix "Look for it in $historyHint."
            continue
        }
        $status = "$($item.Run.properties.status)"
        $runStart = ToUtc $item.Run.properties.startTime
        if ($status -notin $terminalRunStates) {
            RecordCheck -Name $name -Status WARNING -Detail "Still $status after $LogicAppTimeoutMinutes min (started $(FormatTime $runStart))" -Fix "Follow it in $historyHint, or re-run with a higher -LogicAppTimeoutMinutes."
            continue
        }
        $duration = if ($item.Run.properties.endTime) { " in $([int]((ToUtc $item.Run.properties.endTime) - $runStart).TotalSeconds) s" } else { "" }
        if ($status -eq 'Succeeded') {
            RecordCheck -Name $name -Status OK -Detail "Succeeded$duration (started $(FormatTime $runStart))"
            continue
        }
        # Run just now, so a failure is the current state of the installation, not history -
        # MISSING, unlike an old failed run in the Logic Apps check
        $failedAction = GetFailedActionText $item.Workflow "$($item.Run.name)"
        $detail = "$status$duration$(if ($failedAction) { " - $failedAction" } elseif ($item.Run.properties.error.message) { " - $(FirstLine $item.Run.properties.error.message)" })"
        $fix = if ($script:uamiRolesMissing) {
            "Most likely the missing app roles on $uamiName (see above) - assign them, wait out the ~$tokenCacheHours h token cache and re-run with -TriggerLogicApps."
        }
        elseif ($script:latestAppRoleAssignment -and $script:latestAppRoleAssignment.AddHours($tokenCacheHours) -gt [DateTime]::UtcNow) {
            "App roles were assigned $(FormatTime $script:latestAppRoleAssignment) - a 401/403 before $(FormatTime $script:latestAppRoleAssignment.AddHours($tokenCacheHours)) is the token cache: re-run with -TriggerLogicApps then. Otherwise open the run in $historyHint and see Error-handling.md."
        }
        else {
            "Open the run in $historyHint and read the failed action. See Error-handling.md."
        }
        RecordCheck -Name $name -Status MISSING -Detail $detail -Fix $fix
    }
}

# ---------------------------------------------------------------------------
# -TestProvision: order a space through the requests list, follow it, delete it
# ---------------------------------------------------------------------------
$requestsListName = "Provisioning Requests"
$provisioningTypesListName = "Provisioning Types"
$finalRequestStates = @('Space Created', 'Space Creation Failed', 'Space Already Exists', 'Rejected')
# Before ProcessProvisionRequest has picked the request up - the approval flow's states
$unapprovedRequestStates = @('Not Submitted', 'Submitted', 'Pending Approval')
# The SpaceTypeInternal values ProcessProvisionRequest creates a Microsoft 365 group for,
# and the plain SharePoint site types (Check_space_type in processprovisionrequest.json)
$groupSpaceTypes = @('Office 365 Group', 'Project', 'Microsoft Teams Team')
$siteSpaceTypes = @('Team Site', 'Communication Site', 'Hub Site')

# What usually explains a failed run right after an installation, for the Fix lines
function RunFailureHint([string]$Where) {
    if ($script:uamiRolesMissing) {
        return "Most likely the missing app roles on $uamiName (see above) - assign them, wait out the ~$tokenCacheHours h token cache and test again."
    }
    if ($script:latestAppRoleAssignment -and $script:latestAppRoleAssignment.AddHours($tokenCacheHours) -gt [DateTime]::UtcNow) {
        return "App roles were assigned $(FormatTime $script:latestAppRoleAssignment) - a 401/403 before $(FormatTime $script:latestAppRoleAssignment.AddHours($tokenCacheHours)) is the token cache: test again then. Otherwise see $Where and Error-handling.md."
    }
    return "See $Where and Error-handling.md."
}

function GetRequestStatus([int]$Id) {
    $item = Get-PnPListItem -List $requestsListName -Id $Id -Connection $script:siteConnection -ErrorAction Stop
    return [pscustomobject]@{ Item = $item; Status = "$($item.FieldValues['Status'])" }
}

function TestProvisioning {
    $name = "Test order"
    if (-not (RequireSiteConnection $name)) { return }
    $owner = "$script:pnpIdentity"
    if ($owner -notmatch '@') {
        RecordCheck -Name $name -Status UNKNOWN -Detail "Not run - the account signed in to SharePoint could not be read, and it is the owner of the test space"
        return
    }

    # The type, by InternalTitle as in SpaceTypeInternal - or by Title, as the web part shows it
    $types = @(Get-PnPListItem -List $provisioningTypesListName -PageSize 500 -Connection $script:siteConnection -ErrorAction Stop)
    $type = $types | Where-Object { "$($_.FieldValues['InternalTitle'])" -eq $TestProvisionType } | Select-Object -First 1
    if ($null -eq $type) { $type = $types | Where-Object { "$($_.FieldValues['Title'])" -eq $TestProvisionType } | Select-Object -First 1 }
    if ($null -eq $type) {
        $available = @($types | ForEach-Object { "'$($_.FieldValues['InternalTitle'])' ($($_.FieldValues['Title']))" }) -join ', '
        RecordCheck -Name $name -Status WARNING -Detail "Not run - no provisioning type '$TestProvisionType'" -Fix "Pass -TestProvisionType with one of: $available."
        return
    }
    $typeTitle = "$($type.FieldValues['Title'])"
    $typeInternal = "$($type.FieldValues['InternalTitle'])"
    $isGroup = $typeInternal -in $groupSpaceTypes
    if (-not $isGroup -and $typeInternal -notin $siteSpaceTypes) {
        RecordCheck -Name $name -Status WARNING -Detail "Not run - type '$typeInternal' is not supported by -TestProvision" -Fix "Use a group type ($($groupSpaceTypes -join ', ')) or a site type ($($siteSpaceTypes -join ', '))."
        return
    }
    # The web part looks the hub and the template up from the type - not replicated here,
    # so such types are refused rather than ordered half-configured
    $unsupported = @(@('JoinHub', 'DefaultHub', 'TemplateId') | Where-Object { $v = $type.FieldValues[$_]; $v -and "$v" -ne 'False' })
    if ($unsupported.Count -gt 0) {
        RecordCheck -Name $name -Status WARNING -Detail "Not run - type '$typeInternal' has $($unsupported -join ', ') set; -TestProvision does not support hubs or templates yet" -Fix "Test with -TestProvisionType 'Office 365 Group', or order this type through the web part."
        return
    }
    $teamify = $typeInternal -eq 'Microsoft Teams Team' -or ("$($type.FieldValues['Teamify'])" -eq 'True')

    # Approval as in the web part: 'true' (or any other value than 'false') means auto approval
    $autoApprovalValue = ReadSetting 'EnableAutoApproval'
    $autoApproval = $autoApprovalValue -and $autoApprovalValue -cne 'false'
    $managedPath = ReadSetting 'SPOManagedPath'
    if (-not $managedPath) { $managedPath = $parameters.managedPath.Value }

    $stamp = Get-Date -Format 'yyyyMMddHHmmss'
    $alias = "bptest$stamp"
    $spaceTitle = "BP-test $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $siteUrl = "$tenantUrl/$("$managedPath".Trim('/'))/$alias"
    $status = if ($autoApproval) { 'Approved' } else { 'Submitted' }

    # The fields the web part writes (useProvisionDrawer.ts). Add-PnPListItem sets them all,
    # Owners included, in the one request that creates the item - so ProcessProvisionRequest
    # cannot pick an approved request up before its owner is there.
    $values = @{
        Title                   = $spaceTitle
        SpaceDisplayName        = $spaceTitle
        Description             = "Testbestilling fra Test-Installation.ps1 $(Get-Date -Format 'yyyy-MM-dd HH:mm'). Slettes automatisk etter testen."
        BusinessJustification   = ''
        AdditionalInfo          = ''
        SpaceType               = $typeTitle
        SpaceTypeInternal       = $typeInternal
        Teamify                 = $teamify
        TeamsTemplate           = $(if ($teamify) { 'standard' } else { '' })
        Owners                  = @($owner)
        RequestedBy             = @($owner)
        ConfidentialData        = $false
        Visibility              = 'Private'
        ExternalSharingRequired = $false
        Guests                  = ''
        ApplyPnPTemplate        = $false
        ReadOnlyGroup           = $false
        InternalChannel         = $false
        RequestedSource         = 'Test-Installation.ps1'
        SiteURL                 = "$siteUrl, $siteUrl"
        SiteAlias               = $alias
        MailboxAlias            = $alias
        TimeZoneId              = 4
        LCID                    = 1044
        JoinHub                 = $false
        HubSiteTitle            = ''
        HubSite                 = ''
        ParentSite              = ''
        Status                  = $status
        Stage                   = 'Submitted'
        RequestKey              = [guid]::NewGuid().ToString()
    }

    Write-Host ""
    Write-Host "Test order: '$spaceTitle' ($typeTitle) at $siteUrl, owner $owner - $(if ($autoApproval) { 'auto approval is on, so it goes straight to provisioning' } else { 'auto approval is off, so it has to be approved (Teams or Approvals) while this waits' })." -ForegroundColor Yellow
    $created = Add-PnPListItem -List $requestsListName -Values $values -Connection $script:siteConnection -ErrorAction Stop
    $requestId = [int]$created.Id
    Write-Host "  Request $requestId added as '$status' - waiting up to $TestProvisionTimeoutMinutes min. Ctrl+C stops the script, not the order." -ForegroundColor Gray

    $startedAt = [DateTime]::UtcNow
    $deadline = $startedAt.AddMinutes($TestProvisionTimeoutMinutes)
    $current = $null
    $lastStatus = $status
    $finished = $false
    try {
        while ([DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Seconds 15
            try { $current = GetRequestStatus $requestId } catch { continue }
            if ($current.Status -ne $lastStatus) {
                Write-Host "  $(Get-Date -Format 'HH:mm:ss')  $($current.Status)" -ForegroundColor Gray
                if ($current.Status -eq 'Pending Approval') {
                    Write-Host "  Waiting for approval - approve request $requestId in Teams or Approvals." -ForegroundColor Cyan
                }
                $lastStatus = $current.Status
            }
            if ($current.Status -in $finalRequestStates) { break }
        }
        $finished = $true
    }
    finally {
        if (-not $finished) {
            # Ctrl+C: the order goes on in Azure, and nothing below runs to clean it up
            Write-Host "Stopped while waiting - request $requestId ('$spaceTitle', alias $alias) is left as it is. Delete it, and the group or site if one gets created, by hand." -ForegroundColor Yellow
        }
    }
    if ($null -eq $current) {
        try { $current = GetRequestStatus $requestId } catch {}
    }
    $finalStatus = if ($current) { $current.Status } else { $lastStatus }
    $minutes = [math]::Round(([DateTime]::UtcNow - $startedAt).TotalMinutes, 1)

    switch ($finalStatus) {
        'Space Created' {
            $groupId = "$($current.Item.FieldValues['GroupId'])"
            $siteText = $siteUrl
            try {
                if ($null -eq (Get-PnPTenantSite -Url $siteUrl -ErrorAction Stop)) { throw "not found" }
            }
            catch {
                RecordCheck -Name $name -Status WARNING -Detail "'Space Created' after $minutes min, but $siteUrl could not be read ($(FirstLine $_.Exception.Message))" -Fix "Look the space up in the SharePoint admin center. With group language retry on, the site can end up on an alias with a suffix."
                break
            }
            RecordCheck -Name $name -Status OK -Detail "'Space Created' after $minutes min - $siteText$(if ($groupId) { ", group $groupId" })"
        }
        'Space Creation Failed' {
            $reason = FirstLine "$($current.Item.FieldValues['StatusReason'])"
            RecordCheck -Name $name -Status MISSING -Detail "'Space Creation Failed' after $minutes min$(if ($reason) { " - $reason" })" -Fix (RunFailureHint "StatusReason on request $requestId, the ProcessProvisionRequest run history and the ConfigureSpace job")
        }
        'Rejected' {
            RecordCheck -Name $name -Status WARNING -Detail "Rejected by the approver - the approval flow works, the provisioning was not tested" -Fix "Approve the next test order, or turn on EnableAutoApproval for the test."
        }
        'Space Already Exists' {
            RecordCheck -Name $name -Status WARNING -Detail "'Space Already Exists' - something already holds $siteUrl" -Fix "Run the test again - the alias has a timestamp, so this should not repeat."
        }
        default {
            $waitingFor = if ($finalStatus -in $unapprovedRequestStates) { "approval" } else { "ProcessProvisionRequest" }
            $fix = if ($finalStatus -in $unapprovedRequestStates) {
                "Nobody approved it within $TestProvisionTimeoutMinutes min. Check that the approval flow is on (Configuration-guide.md Steg 2) and who gets the approvals (Steg 1) - or turn on EnableAutoApproval for the test."
            }
            elseif ($finalStatus -eq 'Approved') {
                "Approved, but ProcessProvisionRequest never picked it up (it polls every minute). Check that the logic app is enabled and that the bestillingsportalen-spo connection is Connected."
            }
            else {
                "Still being provisioned - follow it in the ProcessProvisionRequest run history, or re-run with a higher -TestProvisionTimeoutMinutes."
            }
            RecordCheck -Name $name -Status WARNING -Detail "Still '$finalStatus' after $TestProvisionTimeoutMinutes min (waiting for $waitingFor)" -Fix $fix
        }
    }

    RemoveTestOrder -RequestId $requestId -Status $finalStatus -Item $(if ($current) { $current.Item }) -IsGroup $isGroup -Alias $alias -SiteUrl $siteUrl
}

# Deletes what the test order created. Never what it did not: the alias carries a
# timestamp, and only the group with exactly that alias, or the site on exactly that URL,
# is deleted.
function RemoveTestOrder([int]$RequestId, [string]$Status, $Item, [bool]$IsGroup, [string]$Alias, [string]$SiteUrl) {
    $name = "Test order: cleanup"

    if ($Status -in $unapprovedRequestStates) {
        # Not approved yet: deleting the request means a late approval cannot create anything
        try {
            Remove-PnPListItem -List $requestsListName -Identity $RequestId -Recycle -Force -Connection $script:siteConnection -ErrorAction Stop | Out-Null
            RecordCheck -Name $name -Status OK -Detail "Request $RequestId was never approved - moved it to the site's recycle bin, so a late approval cannot create the space"
        }
        catch {
            RecordCheck -Name $name -Status WARNING -Detail "Could not delete the unapproved request $RequestId ($(FirstLine $_.Exception.Message))" -Fix "Delete it in the 'Provisioning Requests' list - or reject it - so that a late approval does not create the space."
        }
        return
    }
    if ($Status -notin @('Space Created', 'Space Creation Failed')) {
        if ($Status -in @('Approved', 'Space Creation')) {
            RecordCheck -Name $name -Status WARNING -Detail "Nothing deleted - request $RequestId was still '$Status', and deleting under the logic app would only leave debris" -Fix "When it has finished: delete the Microsoft 365 group or site with alias '$Alias' ($SiteUrl)."
        }
        return
    }

    if ($IsGroup) {
        if (-not $script:cliSignedIn) {
            RecordCheck -Name $name -Status WARNING -Detail "The test group was not deleted - the Azure CLI is not signed in" -Fix "Delete the Microsoft 365 group with alias '$Alias' (Entra ID or the Microsoft 365 admin center)."
            return
        }
        $groupId = if ($Item) { "$($Item.FieldValues['GroupId'])" } else { '' }
        if (-not $groupId) {
            # A failed order may have created the group before it failed
            $lookup = GraphGet "groups" @("`$filter=mailNickname eq '$Alias'", '$select=id')
            if ($lookup.Ok) { $groupId = "$(@($lookup.Data.value | Select-Object -First 1).id)" }
        }
        if (-not $groupId) {
            RecordCheck -Name $name -Status OK -Detail "No group with alias '$Alias' was created - nothing to delete"
            return
        }
        $delete = InvokeAz rest --method delete --url "https://graph.microsoft.com/v1.0/groups/$groupId"
        if ($delete.Ok) {
            RecordCheck -Name $name -Status OK -Detail "Deleted the test group '$Alias' ($groupId) and with it its site - restorable for 30 days under Entra ID -> Groups -> Deleted groups"
        }
        else {
            RecordCheck -Name $name -Status WARNING -Detail "Could not delete the test group '$Alias' ($groupId): $($delete.Error)" -Fix "Delete it by hand (Entra ID or the Microsoft 365 admin center). The account signed in to the Azure CLI must be an owner of the group, or Groups Administrator."
        }
        return
    }

    try {
        if ($null -eq (Get-PnPTenantSite -Url $SiteUrl -ErrorAction SilentlyContinue)) {
            RecordCheck -Name $name -Status OK -Detail "No site at $SiteUrl was created - nothing to delete"
            return
        }
        Remove-PnPTenantSite -Url $SiteUrl -Force -ErrorAction Stop
        RecordCheck -Name $name -Status OK -Detail "Moved the test site $SiteUrl to the tenant recycle bin (restorable for 93 days)"
    }
    catch {
        RecordCheck -Name $name -Status WARNING -Detail "Could not delete the test site $SiteUrl ($(FirstLine $_.Exception.Message))" -Fix "Delete it in the SharePoint admin center -> Active sites."
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if ($TriggerLogicApps -or $TestProvision) {
    $changes = @(@(if ($TriggerLogicApps) { 'the scheduled logic apps are run' }) + @(if ($TestProvision) { 'a test space is ordered and deleted' })) -join ' and '
    Write-Host "###  POST-INSTALLATION CHECK STARTED (read-only, except that $changes)  ###" -ForegroundColor Magenta
}
else {
    Write-Host "###  POST-INSTALLATION CHECK STARTED (read-only - nothing is changed)  ###" -ForegroundColor Magenta
}

# PnP.PowerShell 3.2+, as deploy.ps1 requires. Az PowerShell is not used here - if it
# ever is, import PnP.PowerShell BEFORE the first Az cmdlet (see the assembly-conflict
# comment in deploy.ps1).
$pnpModule = Get-Module -Name PnP.PowerShell
if ($null -eq $pnpModule) {
    try {
        $pnpModule = Import-Module PnP.PowerShell -PassThru -ErrorAction Stop
    }
    catch {
        Write-Host "PnP.PowerShell could not be loaded ($(FirstLine $_.Exception.Message)). Install it with: Install-Module PnP.PowerShell -Scope CurrentUser" -ForegroundColor Red
        exit 1
    }
}
if ([version](("$($pnpModule.Version)" -split '-')[0]) -lt [version]'3.2.0') {
    Write-Host "PnP.PowerShell $($pnpModule.Version) is loaded, but 3.2.0 or newer is required. Update it with: Update-Module PnP.PowerShell - in a new session." -ForegroundColor Red
    exit 1
}

try {
    $parameters = Get-Content -LiteralPath $ParametersPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-Host "Could not read $parametersFileName ($(FirstLine $_.Exception.Message))." -ForegroundColor Red
    exit 1
}

$invalid = @(@('tenantId', 'spoTenantName', 'managedPath', 'pnpAppId') | Where-Object { -not (IsValidParam $parameters.$_) })
if (-not (IsValidParam $parameters.requestsSiteAlias) -and -not (IsValidParam $parameters.requestsSiteName)) { $invalid += 'requestsSiteAlias/requestsSiteName' }
if ($invalid.Count -gt 0) {
    Write-Host "$parametersFileName lacks $($invalid -join ', ') - nothing can be checked without them." -ForegroundColor Red
    exit 1
}

if ($parameters.PSObject.Properties.Name -contains 'uamiName' -and (IsValidParam $parameters.uamiName)) {
    $uamiName = $parameters.uamiName.Value
}

# Same alias logic as deploy.ps1: requestsSiteAlias, falling back to the title-derived
# alias for parameter files from before the parameter existed
if ($parameters.PSObject.Properties.Name -contains 'requestsSiteAlias' -and (IsValidParam $parameters.requestsSiteAlias)) {
    $requestsSiteAlias = ($parameters.requestsSiteAlias.Value -replace ' ', '').Trim().Trim('/')
}
else {
    $requestsSiteAlias = $parameters.requestsSiteName.Value -replace (' ', '')
}
$tenantUrl = "https://$($parameters.spoTenantName.Value).sharepoint.com"
$adminSiteUrl = "https://$($parameters.spoTenantName.Value)-admin.sharepoint.com"
$requestsSiteUrl = "$tenantUrl/$($parameters.managedPath.Value)/$requestsSiteAlias"

# The Azure checks need the subscription and resource group. Without them (typically
# after deploy.ps1 -SharePointOnly) there is nothing in Azure to check - which is MISSING
# for a full installation.
$azureParametersMissing = @(@('subscriptionId', 'resourceGroupName') | Where-Object { -not (IsValidParam $parameters.$_) })
$checkAzure = -not $SharePointOnly -and $azureParametersMissing.Count -eq 0
$subscriptionId = if (IsValidParam $parameters.subscriptionId) { $parameters.subscriptionId.Value } else { $null }
$resourceGroupName = if (IsValidParam $parameters.resourceGroupName) { $parameters.resourceGroupName.Value.Replace(" ", "") } else { $null }
$rgPath = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName"
$automationPath = "$rgPath/providers/Microsoft.Automation/automationAccounts/$automationAccountName"

# --- Azure CLI ---
# An existing session in the target tenant (and subscription) is reused without asking -
# nothing is written, so there is nothing to confirm. The CLI's default subscription is
# switched for the run (az ad / Graph calls follow it) and restored at the end.
$previousCliSubscription = (InvokeAz account show --query id --output tsv).Output
$script:cliSignedIn = $false
$script:cliError = $null
$cliUser = $null
try {
    $findTarget = {
        $accounts = @()
        $listed = InvokeAz account list --output json
        if ($listed.Ok -and $listed.Output) { $accounts = @($listed.Output | ConvertFrom-Json) }
        if ($checkAzure) {
            return $accounts | Where-Object { $_.id -eq $subscriptionId -and $_.tenantId -eq $parameters.tenantId.Value } | Select-Object -First 1
        }
        return $accounts | Where-Object { $_.tenantId -eq $parameters.tenantId.Value } | Select-Object -First 1
    }
    $target = & $findTarget
    if ($null -eq $target) {
        Write-Host "Launching Azure CLI sign-in (tenant $($parameters.tenantId.Value))..." -ForegroundColor Yellow
        # Not through InvokeAz: whatever az login has to say while signing in must reach
        # the console
        $loginArgs = @('login', '--tenant', $parameters.tenantId.Value, '--only-show-errors')
        if (-not $checkAzure) { $loginArgs += '--allow-no-subscriptions' }
        az @loginArgs | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "az login failed - see the error above" }
        $target = & $findTarget
    }
    if ($null -eq $target) {
        throw $(if ($checkAzure) { "the signed-in account has no access to subscription $subscriptionId in tenant $($parameters.tenantId.Value)" } else { "no Azure CLI session in tenant $($parameters.tenantId.Value)" })
    }
    $set = InvokeAz account set --subscription $target.id
    if (-not $set.Ok) { throw "az account set failed ($($set.Error))" }
    $script:cliSignedIn = $true
    $cliUser = "$($target.user.name)"
    Write-Host "Azure CLI: $cliUser$(if ($checkAzure) { " - subscription '$($target.name)'" })" -ForegroundColor Green
}
catch {
    $script:cliError = FirstLine $_.Exception.Message
    Write-Host "Azure CLI sign-in did not complete ($script:cliError) - the Azure and Entra ID checks will report it." -ForegroundColor Yellow
}

# --- PnP ---
Write-Host "Launching PnP sign-in (a browser window may open - sign in with a SharePoint Administrator)..." -ForegroundColor Yellow
$script:pnpConnectError = $null
$script:spoAdminAccessError = $null
$script:pnpIdentity = $null
try {
    Connect-PnPOnline -Url $adminSiteUrl -ClientId $parameters.pnpAppId.Value -Interactive -ErrorAction Stop
    try {
        # No Get-PnPCurrentUser in PnP.PowerShell 3.x - read Web.CurrentUser over CSOM
        $pnpContext = Get-PnPContext
        $currentUser = $pnpContext.Web.CurrentUser
        $pnpContext.Load($currentUser)
        $pnpContext.ExecuteQuery()
        $script:pnpIdentity = if ($currentUser.Email) { $currentUser.Email } else { ("$($currentUser.LoginName)" -split '\|')[-1] }
    }
    catch {
        $script:pnpIdentity = "(could not be read)"
    }
    # Connect-PnPOnline does not throw when it completes silently from the on-disk token
    # cache as an account with no rights here - probe the tenant admin API, as deploy.ps1 does
    try { Get-PnPTenantSite -Url $tenantUrl -ErrorAction Stop | Out-Null }
    catch { $script:spoAdminAccessError = FirstLine $_.Exception.Message }
}
catch {
    $script:pnpConnectError = FirstLine $_.Exception.Message
}

Write-Host ""
Write-Host "  Parameter file:     $parametersFileName"
Write-Host "  Entra ID tenant:    $(if (IsValidParam $parameters.fullTenantName) { "$($parameters.fullTenantName.Value) " })($($parameters.tenantId.Value))"
Write-Host "  Requests site:      $requestsSiteUrl"
if ($checkAzure) {
    Write-Host "  Resource group:     $resourceGroupName (subscription $subscriptionId)"
}
Write-Host "  Signed in (CLI):    $(if ($cliUser) { $cliUser } else { '(not signed in)' })"
Write-Host "  Signed in (PnP):    $(if ($script:pnpIdentity) { $script:pnpIdentity } else { '(not signed in)' })"
Write-Host "  Service account:    $(if (IsValidParam $parameters.serviceAccountUPN) { $parameters.serviceAccountUPN.Value } else { '(not set)' })"
Write-Host "  Version (checkout): $(if ($repoVersion) { $repoVersion } else { 'unknown' })"
Write-Host ""
Write-Host "Running the checks (SharePoint, SPFx, app roles, Automation, API connections, Logic Apps - takes a minute$(if ($TriggerLogicApps) { ", plus up to $LogicAppTimeoutMinutes min for the logic app runs" })$(if ($TestProvision) { ", plus up to $TestProvisionTimeoutMinutes min for the test order" }))..." -ForegroundColor Yellow

try {
    # --- Sign-ins ---
    if (-not $script:cliSignedIn) {
        RecordCheck -Name "Sign-in: Azure CLI" -Status MISSING -Detail "$script:cliError - the Azure and Entra ID checks cannot answer" -Fix "Sign in with az login --tenant $($parameters.tenantId.Value)$(if ($checkAzure) { " with an account that has Reader on $resourceGroupName" }), then re-run."
    }
    else {
        RecordCheck -Name "Sign-in: Azure CLI" -Status OK -Detail "$cliUser"
    }
    CheckSpoAdminAccess

    # --- SharePoint ---
    if ($script:pnpConnectError) {
        RecordCheck -Name "SharePoint checks" -Status SKIPPED -Detail "No PnP connection - see the sign-in item above"
    }
    else {
        RunCheck "SharePoint: requests site" { CheckRequestsSite }
        ConnectRequestsSite
        RunCheck "SharePoint: lists" { CheckLists }
        RunCheck "SharePoint: installed version" { CheckInstalledVersion }
        ConnectAppCatalog
        RunCheck "SharePoint: registered in $registryKey" { CheckRegistry }
        ResolveServiceAccount
        RunCheck "SharePoint: service account in the site's Microsoft 365 group" { CheckServiceAccountGroup }
        RunCheck "SharePoint: service account is site collection admin" { CheckServiceAccountSiteAdmin }

        # --- SPFx ---
        RunCheck "SPFx packages" { CheckSpfxPackages }
        RunCheck "Teams app" { CheckTeamsApp }
    }

    # --- Azure ---
    if ($SharePointOnly) {
        RecordCheck -Name "Azure checks" -Status SKIPPED -Detail "-SharePointOnly: app roles, Automation, API connections and Logic Apps are not checked"
    }
    elseif ($azureParametersMissing.Count -gt 0) {
        RecordCheck -Name "Azure checks" -Status MISSING -Detail "$($azureParametersMissing -join ' and ') not set in $parametersFileName - the Azure part cannot be checked, and is presumably not installed" -Fix "Fill them in and run deploy.ps1 without -SharePointOnly - or check only the SharePoint part with -SharePointOnly."
    }
    elseif (-not $script:cliSignedIn) {
        RecordCheck -Name "Azure checks" -Status SKIPPED -Detail "The Azure CLI is not signed in - see the sign-in item above"
    }
    else {
        RunCheck "Automation: account $automationAccountName" { CheckAutomationAccount }
        RunCheck "Automation: runtime environment $runtimeEnvironmentName" { CheckRuntimeEnvironment }
        foreach ($runbook in @($repoRunbooks + $customerRunbook)) {
            RunCheck "Automation: runbook $runbook" { CheckRunbook $runbook }
        }
        RunCheck "Managed identity: $uamiName" { CheckUami }

        $script:appRoleSetupError = $null
        $script:latestAppRoleAssignment = $null
        $script:uamiRolesMissing = $false
        try {
            $expectedRoles = GetExpectedAppRoles
            $script:resourceSps = GetResourceServicePrincipals
        }
        catch {
            $script:appRoleSetupError = "Could not determine the expected or assigned roles ($(FirstLine $_.Exception.Message))"
            $expectedRoles = @{ Automation = @{}; Uami = @{} }
        }
        RunCheck "App roles: $automationAccountName (system-assigned)" { CheckAppRoles -Label "$automationAccountName (system-assigned)" -PrincipalId $script:automationPrincipalId -ParameterName 'AutomationIdentityId' -Expected $expectedRoles.Automation }
        RunCheck "App roles: $uamiName (user-assigned)" { CheckAppRoles -Label "$uamiName (user-assigned)" -PrincipalId $script:uamiPrincipalId -ParameterName 'UamiId' -Expected $expectedRoles.Uami }

        foreach ($connection in @($delegatedConnections + $automationConnection)) {
            RunCheck "API connection: $connection" { CheckApiConnection $connection }
        }
        # Before the Logic Apps check, so its 'latest run' is the run started here.
        # After the app roles, so a failure can be put down to missing roles.
        if ($TriggerLogicApps) {
            RunCheck "Logic App runs" { InvokeScheduledLogicApps }
        }
        RunCheck "Logic Apps" { CheckLogicApps }
    }

    # --- Test order ---
    if ($TestProvision) {
        $missingSoFar = @($script:checks | Where-Object Status -eq 'MISSING')
        if ($script:pnpConnectError -or -not $checkAzure -or -not $script:cliSignedIn) {
            RecordCheck -Name "Test order" -Status SKIPPED -Detail "Not run - it needs both the SharePoint and the Azure CLI sign-in, and the Azure part (see above)"
        }
        elseif ($missingSoFar.Count -gt 0) {
            # It would fail on what is missing, and leave a half-created group behind
            RecordCheck -Name "Test order" -Status SKIPPED -Detail "Not run - $($missingSoFar.Count) item(s) above are MISSING, and the order would fail on them" -Fix "Fix the MISSING items, then re-run with -TestProvision."
        }
        else {
            RunCheck "Test order" { TestProvisioning }
        }
    }

    # --- Manual ---
    $flowOwner = if (IsValidParam $parameters.serviceAccountUPN) { $parameters.serviceAccountUPN.Value } else { "the service account" }
    RecordCheck -Name "Manual: approval flow" -Status SKIPPED -Detail "Lives in Power Automate, which cannot be read from here" -Fix "make.powerautomate.com as $flowOwner -> Solutions -> 'Bestillingsportalen Flows': 'Provisioning Request Approval' is there and turned On (Configuration-guide.md Steg 2)."
    $tokenNote = if ($script:latestAppRoleAssignment) {
        " App roles were assigned $(FormatTime $script:latestAppRoleAssignment): until $(FormatTime $script:latestAppRoleAssignment.AddHours($tokenCacheHours)) sporadic 401/403 are the ~$tokenCacheHours h token cache - wait and test again rather than troubleshoot."
    }
    else {
        " Within ~$tokenCacheHours h of an app role assignment, sporadic 401/403 are the managed identity token cache - wait and test again rather than troubleshoot."
    }
    $testOrderPassed = @($script:checks | Where-Object { $_.Name -eq 'Test order' -and $_.Status -eq 'OK' }).Count -gt 0
    $manualDetail = if ($testOrderPassed) { "The provisioning works (see 'Test order') - what is left is the web part and the access as an ordinary user" } else { "End to end - the only test that covers the approval, the Logic Apps and the runbooks together" }
    RecordCheck -Name "Manual: test order" -Status SKIPPED -Detail $manualDetail -Fix "Order a space as an ordinary user, approve it, and follow the status to 'Space Created' (Configuration-guide.md Steg 8).$tokenNote"

    $missingCount = ShowChecklist
}
finally {
    if ($previousCliSubscription -and $script:cliSignedIn) {
        InvokeAz account set --subscription $previousCliSubscription | Out-Null
    }
}

if ($TriggerLogicApps -or $TestProvision) {
    Write-Host "Nothing else has been changed in the environment than that $(@(@(if ($TriggerLogicApps) { 'the scheduled logic apps were run (-TriggerLogicApps)' }) + @(if ($TestProvision) { 'a test space was ordered and deleted (-TestProvision) - see the cleanup item' })) -join ' and ')." -ForegroundColor Cyan
}
else {
    Write-Host "Read-only check: nothing has been changed in the environment." -ForegroundColor Cyan
}
if ($missingCount -gt 0) {
    Write-Host "Fix the $missingCount missing item(s) above and re-run." -ForegroundColor Yellow
    exit 1
}
$unknownCount = @($script:checks | Where-Object Status -eq 'UNKNOWN').Count
if ($unknownCount -gt 0) {
    Write-Host "Nothing is reported missing, but $unknownCount item(s) could not be checked (UNKNOWN) - see the reasons above. The signed-in accounts may lack read access." -ForegroundColor Yellow
}
else {
    Write-Host "Nothing is missing - finish with the manual items (SKIPPED) above, ending with the test order." -ForegroundColor Green
}
exit 0
