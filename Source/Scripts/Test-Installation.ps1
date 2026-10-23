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

    The script NEVER creates, changes or deletes anything in the environment. Every
    lookup is a read; a lookup that fails is reported as UNKNOWN or WARNING, never as a
    crash, and the remaining checks still run. The only local change is the Azure CLI's
    default subscription, which is switched to the target for the run and restored at
    the end.

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

.EXAMPLE
    ./Test-Installation.ps1

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
    [switch]$SharePointOnly # Check the SharePoint part only - see the help
)

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
# Earlier display names (package-solution.json 'name') per solution id. The SPFx check
# finds packages by name, so add the old name here when a solution is renamed.
$previousSpfxNames = @{
    '00b53018-61b2-4576-b559-27df9321cfc8' = @('Bestillingsportalen - Provision Web Parts')
}

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
            # Matched on the solution NAME. Get-PnPApp returns PnP.Framework's AppMetadata,
            # which has no ProductId: its Id is the app catalog's own id for the package
            # (AvailableApps 'ID'), not the solution id in package-solution.json, so an id
            # comparison never matched - at a customer 23.10.2026 a deployed package was
            # reported as missing. Title is the solution name from package-solution.json,
            # which is what the app catalog shows. The id is still tried first, for the
            # case where the two happen to be the same.
            # Names a solution has been published under before, so an environment that
            # has not been redeployed since a rename is still found.
            $knownNames = @("$($package.name)") + @($previousSpfxNames["$($package.id)"] | Where-Object { $_ })
            $app = $apps | Where-Object { "$($_.Id)" -eq "$($package.id)" } | Select-Object -First 1
            if ($null -eq $app) {
                $app = $apps | Where-Object { "$($_.Title)" -in $knownNames } | Select-Object -First 1
            }
            $fix = "Run deploy.ps1 -Upgrade (or -SkipSPFxBuild to publish an already built package) - or upload the .sppkg to $script:appCatalogUrl and deploy it."
            if ($null -eq $app) {
                RecordCheck -Name $name -Status MISSING -Detail "No app named '$($knownNames -join "' or '")' in the tenant app catalog" -Fix $fix
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
            if ("$($app.Title)" -ne "$($package.name)") {
                RecordCheck -Name $name -Status WARNING -Detail "'$($app.Title)' $($app.AppCatalogVersion) is deployed under its old name - this checkout names it '$($package.name)'" -Fix "Nothing breaks. Re-run deploy.ps1 -Upgrade (or -SkipSPFxBuild) to publish it under the new name."
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
# Main
# ---------------------------------------------------------------------------
Write-Host "###  POST-INSTALLATION CHECK STARTED (read-only - nothing is changed)  ###" -ForegroundColor Magenta

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
Write-Host "Running the checks (SharePoint, SPFx, app roles, Automation, API connections, Logic Apps - takes a minute)..." -ForegroundColor Yellow

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
        RunCheck "Logic Apps" { CheckLogicApps }
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
    RecordCheck -Name "Manual: test order" -Status SKIPPED -Detail "End to end - the only test that covers the approval, the Logic Apps and the runbooks together" -Fix "Order a space as an ordinary user, approve it, and follow the status to 'Space Created' (Configuration-guide.md Steg 8).$tokenNote"

    $missingCount = ShowChecklist
}
finally {
    if ($previousCliSubscription -and $script:cliSignedIn) {
        InvokeAz account set --subscription $previousCliSubscription | Out-Null
    }
}

Write-Host "Read-only check: nothing has been changed in the environment." -ForegroundColor Cyan
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
