<#
.SYNOPSIS
    Deploys the following assets of the Bestillingsportalen solution -

        -SharePoint Site & Assets
        -User-assigned managed identity (used by the Logic Apps for Graph/SharePoint/Azure Automation)
        -Azure Automation Account & Runbooks
        -Logic App

.DESCRIPTION
    Deploys the Bestillingsportalen solution (excluding Flows).
    This script uses the Azure CLI, Azure Az PowerShell and PnP PowerShell Modules to perform the deployment.

    Everything authenticates with managed identity - no certificate, client secret or Key Vault.
    Sensitivity labels are applied app-only by the ConfigureSpace runbook, so the solution no longer
    needs an Entra ID app registration or a non-MFA service account.

    The account running this script must be able to grant app roles to the managed identities
    (e.g. Global Administrator, or Privileged Role Administrator + Cloud Application Administrator).

    The script requires input during execution, requires sign-in to a number of services and therefore should be monitored.

    Parameters should be filled out in the parameters file before executing the script
    (default .\parameters.json - see -ParametersPath).

.PARAMETER ParametersPath
    Path to the parameters file to deploy from. Default: .\parameters.json.

    Use this to keep one file per customer environment (parameters-<customer>.json,
    all ignored by git) instead of copying the right one over parameters.json before
    every run. The path is resolved before anything else happens, so a typo fails
    immediately rather than after three sign-ins.

.PARAMETER Preflight
    Run ONLY the pre-deployment checks and print the checklist, then exit without
    deploying anything - a quick way to see what is missing before booking time for
    the real run. Exit code 0 when nothing is missing, 1 otherwise. The checks need
    the same sign-ins as a deployment (Az, Azure CLI, PnP), but nothing is created
    or changed.

.PARAMETER SkipAppRoles
    Skip assigning Graph/SharePoint app roles to the managed identities - the one
    step that requires Global Administrator (or Privileged Role Administrator +
    Cloud Application Administrator). Use this when the account running the
    deployment does not have those rights: everything else deploys, and the script
    prints a ready-to-run AssignPermissionsToManagedIdentity.ps1 command (object
    ids filled in) to hand to a Global Administrator. The logic apps get 401/403
    at runtime until that command has been run.

.PARAMETER SkipConfirmation
    Skip the pre-flight summary/confirmation prompt, and reuse a cached Az/Azure CLI
    session matching the target tenant without asking.

.PARAMETER Force
    Fully unattended. Implies -SkipConfirmation, and answers the "site already exists -
    re-apply the PnP provisioning template?" prompt with NO, so configuration lists keep
    their current content.

    -Force means "do not stop to ask me anything", NOT "answer yes to everything": it
    will not purge a soft-deleted site, purge a soft-deleted Microsoft 365 group, or
    delete an active group and its site. Those are irreversible, so -Force aborts with a
    message instead - re-run without it to decide.

.EXAMPLE
    deploy.ps1

.EXAMPLE
    deploy.ps1 -Upgrade -Force
    Unattended upgrade of an existing environment: no prompts, no template re-apply.

.EXAMPLE
    deploy.ps1 -ParametersPath .\parameters-gjesdal.json
    Deploy using a specific customer's parameter file.
#>

<# Valid Azure locations that support Azure Automation & Logic Apps at the time of writing - https://azure.microsoft.com/en-gb/global-infrastructure/services/?products=logic-apps,automation&regions=all #>

param
(
    [Parameter(Mandatory = $false)]
    [string]$ParametersPath = ".\parameters.json", # Parameter file to deploy from - one per customer environment
    [switch]$SkipVerifyModules,
    [switch]$SkipSharepointSite,
    [switch]$SkipBicepDeploy,
    [switch]$SkipCreateResourceGroup,
    [switch]$SkipDeployARMTemplates,
    [switch]$SkipDeployAPIConnections,
    [switch]$Preflight, # Run only the pre-deployment checks, print the checklist, exit - see the help
    [switch]$SkipAppRoles, # Skip app role assignment (needs GA) and print a handover command instead - see the help
    [switch]$SkipSPFxDeploy,
    [switch]$SkipConfirmation, # Skip the pre-flight summary/confirmation prompt (for unattended runs)
    [switch]$Force, # Fully unattended: implies -SkipConfirmation, and never re-applies the PnP template. See below.
    [switch]$Upgrade  # See Upgrade.md for details on using upgrade mode
)

# -Force means "do not stop to ask me anything", not "answer yes to everything".
#
# It reuses cached sign-in sessions, skips the pre-flight confirmation, and answers the
# "site already exists - apply the PnP provisioning template?" prompt with NO, so an
# unattended run never changes the site's schema as a side effect. (Applying the
# template never resets list content - the DataRows use UpdateBehavior="Skip".)
#
# It deliberately does NOT auto-approve the three destructive prompts in
# CreateRequestsSharePointSite (purging a soft-deleted site, purging a soft-deleted
# Microsoft 365 group, or permanently deleting an ACTIVE group and its site). Those are
# irreversible and can destroy a real site, so with -Force they abort with a message
# telling you to re-run interactively and decide.
if ($Force) {
    $SkipConfirmation = $true
    Write-Host "-Force: running unattended. Cached sessions are reused, the pre-flight confirmation is skipped, and the PnP template will NOT be re-applied to an existing site." -ForegroundColor Yellow
    Write-Host "        Destructive prompts (purging a deleted site or group, deleting an active group) still abort - re-run without -Force to decide on those." -ForegroundColor Yellow
}

Add-Type -AssemblyName System.Web

# Ensure running on PowerShell 7.4+ (required by PnP.PowerShell 3.x)
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version]'7.4') {
    Write-Host "This script requires PowerShell 7.4 or newer (current: $($PSVersionTable.PSVersion)). Install the latest PowerShell from https://aka.ms/powershell and re-run in a new session." -ForegroundColor Red
    exit 1
}

# Resolve the parameter file up front. The file is not read until much later (after
# the module checks and all three sign-ins), so validating it here turns a typo into
# an immediate error instead of one discovered after three MFA prompts. Resolved to a
# full path because the working directory is assumed to be Scripts\ elsewhere.
$resolvedParametersPath = Resolve-Path -LiteralPath $ParametersPath -ErrorAction SilentlyContinue
if ($null -eq $resolvedParametersPath) {
    Write-Host "Parameter file '$ParametersPath' was not found." -ForegroundColor Red
    Write-Host "Run this script from the Scripts folder, and generate the file with ./GenerateParameters.ps1 if it does not exist yet." -ForegroundColor Yellow
    $candidates = @(Get-ChildItem -Path $PSScriptRoot -Filter 'parameters*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'parameters.template.json' } | Select-Object -ExpandProperty Name)
    if ($candidates.Count -gt 0) {
        Write-Host "Parameter files found next to the script: $($candidates -join ', ')" -ForegroundColor Yellow
    }
    exit 1
}
$ParametersPath = $resolvedParametersPath.Path
$parametersFileName = Split-Path -Leaf $ParametersPath

# Check for presence of Azure CLI (cross-platform)
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "AZURE CLI NOT INSTALLED!`nPLEASE INSTALL THE CLI FROM https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest and re-run this script in a new PowerShell session" -ForegroundColor Red
    exit 1
}

# Variables
$packageRootPath = "..\"
$imagesDir = "Assets\ProvTypesImages"
$iconsDir = "Assets\ProvTypesIcons"
$templatePath = "Templates\Bestillingsportalen.xml"

# Required PS modules (value = minimum version; $null = any version).
# PnP.PowerShell 3.2+ is required for the interactive/persisted login used by ConnectPnP.
$preReqModules = [ordered]@{
    'PnP.PowerShell' = [version]'3.2.0'
    'Az'             = $null
    'WriteAscii'     = $null
}

#  lists
$requestsListName = "Provisioning Requests"
$requestSettingsListName = "Provisioning Request Settings"
$siteAssetsListURL = "SiteAssets"
$provTypesListName = "Provisioning Types"
$siteTemplatesListName = "Site Templates"
$hubSitesListName = "Hub Sites"
$teamsTemplatesListName = "Teams Templates"
$ipLabelsListName = "IP Labels"
$guestRequestsListName = "Guest Requests"

#  Folder names
$provRequestsFolderName = "Provisioning Request"
$provTypesImageFolderName = "ProvTypesImages"
$provTypesIconFolderName = "ProvTypesIcons"

#  Field names
$TitleFieldName = "Title"
$SpaceTitleFieldName = "Space Title"
$RequirementFieldName = "Requirement"

$imageFolderUpload = "$siteAssetsListURL/$provRequestsFolderName/$provTypesImageFolderName"
$iconFolderUpload = "$siteAssetsListURL/$provRequestsFolderName/$provTypesIconFolderName"

$automationAccountName = "bestillingsportalen-auto"
$runtimeEnvironmentName = "bestillingsportalen-ps74" # Keep in sync with runbooks.bicep
$uamiName = "bestillingsportalen-uami" # Overridden by the uamiName parameter in the parameter file if present

# Solution version. VERSION in the repo root is the single source of truth - bump it
# there, never here (the release routine is in CONTRIBUTING.md). A missing or malformed
# file must never block a customer install, so this falls back to "unknown" and records
# the reason for CheckVersionFile to surface in the pre-deployment checklist.
$versionFilePath = Join-Path $PSScriptRoot "..\..\VERSION"
$deployVersion = "unknown"
$script:versionFileIssue = $null
$script:previousInstalledVersion = $null
if (-not (Test-Path $versionFilePath)) {
    $script:versionFileIssue = "VERSION was not found at $versionFilePath"
}
else {
    $rawVersion = "$(Get-Content $versionFilePath -Raw -ErrorAction SilentlyContinue)".Trim()
    if ($rawVersion -match '^\d+\.\d+\.\d+$') {
        $deployVersion = $rawVersion
    }
    else {
        $script:versionFileIssue = "VERSION contains '$rawVersion', which is not a MAJOR.MINOR.PATCH version"
    }
}

# Settings list rows that carry the version stamp. Written by StampInstalledVersion,
# deliberately NOT seeded by the PnP template - see the comment on that function.
$installedVersionSettingName = "InstalledVersion"
$installedDateSettingName = "InstalledDate"

# Global variables
$global:context = $null
$global:requestsListId = $null
$global:requestsSettingsListId = $null
$global:siteTemplatesListId = $null
$global:hubSitesListId = $null
$global:teamsTemplatesListId = $null
$global:teamsAppManualUploadZip = $null
$global:guestRequestsListId = $null
$global:uamiPrincipalId = $null
$global:tenantUrl = $null
$global:upgrade = $false
$global:skipApplyTemplate = $false

# Validates if a parameter in the json file is valid
function IsValidParam {
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory = $true)]
        $param
    )

    return -not([string]::IsNullOrEmpty($param.Value)) -and ($param.Value -ne '<<value>>')
}

function IsValidGuid {
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$ObjectGuid
    )

    # Define verification regex
    [regex]$guidRegex = '(?im)^[{(]?[0-9A-F]{8}[-]?(?:[0-9A-F]{4}[-]?){3}[0-9A-F]{12}[)}]?$'

    # Check guid against regex
    return $ObjectGuid -match $guidRegex
}

# Validate input parameters.
function ValidateParameters {
    $isValid = $true

    if (-not(IsValidParam($parameters.tenantId)) -or -not(IsValidGuid -ObjectGuid $parameters.tenantId.Value)) {
        Write-Host "Invalid tenantId. This should be a GUID" -ForegroundColor Red
        $isValid = $false;
    }

    if (-not (IsValidParam($parameters.spoTenantName))) {
        Write-Host "Invalid spoTenantName" -ForegroundColor Red
        $isValid = $false;
    }

    if (-not (IsValidParam($parameters.requestsSiteName))) {
        Write-Host "Invalid requestsSiteName" -ForegroundColor Red
        $isValid = $false;
    }

    if (-not (IsValidParam($parameters.requestsSiteDesc))) {
        Write-Host "Invalid requestsSiteDesc" -ForegroundColor Red
        $isValid = $false;
    }

    if (-not (IsValidParam($parameters.managedPath))) {
        Write-Host "Invalid managedPath" -ForegroundColor Red
        $isValid = $false;
    }

    if (-not(IsValidParam($parameters.subscriptionId)) -or -not(IsValidGuid -ObjectGuid $parameters.subscriptionId.Value)) {
        Write-Host "Invalid subscriptionId. This should be a GUID." -ForegroundColor Red
        $isValid = $false;
    }

    if (-not (IsValidParam($parameters.region))) {
        Write-Host "Invalid region" -ForegroundColor Red
        $isValid = $false;
    }

    if (-not (IsValidParam($parameters.resourceGroupName))) {
        Write-Host "Invalid resourceGroupName" -ForegroundColor Red
        $isValid = $false;
    }

    if (-not (IsValidParam($parameters.serviceAccountUPN))) {
        Write-Host "Invalid serviceAccountUPN" -ForegroundColor Red
        $isValid = $false;
    }

    if (-not (IsValidParam($parameters.pnpAppId))) {
        Write-Host "Invalid pnpAppId" -ForegroundColor Red
        $isValid = $false;
    }

    if (-not (IsValidParam($parameters.fullTenantName))) {
        Write-Host "Invalid fullTenantName" -ForegroundColor Red
        $isValid = $false;
    }

    return $isValid
}

# Verifies that the required PowerShell modules are usable in THIS session - throws if one
# is missing or too old.
#
# There are three ways a module can be usable, and they see different things:
#   Get-Module               - loaded in this session. A copy side-loaded from outside
#                              PSModulePath (Import-Module by path, which is how you test a
#                              new PnP release) shows up ONLY here.
#   Get-Module -ListAvailable- on PSModulePath, so Import-Module will find it.
#   Get-InstalledModule      - registered by PowerShellGet. The narrowest of the three: it
#                              misses anything unzipped by hand, which used to make this
#                              function report "not installed" about a module that was
#                              loaded and working.
# A loaded module wins outright, even over a newer one on disk: PowerShell will not load a
# second version into the same session, so the loaded one is what the run will actually use.
function VerifyModules {
    foreach ($module in $preReqModules.Keys) {
        $source = $null
        $found = Get-Module -Name $module -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $found) {
            $source = "loaded in this session from $($found.ModuleBase)"
        }
        else {
            $candidates = @()
            $candidates += Get-Module -Name $module -ListAvailable -ErrorAction SilentlyContinue
            $candidates += Get-InstalledModule -Name $module -ErrorAction SilentlyContinue
            $found = @($candidates | Where-Object { $null -ne $_ }) |
                Sort-Object { [version](("$($_.Version)" -split '-')[0]) } -Descending |
                Select-Object -First 1
            if ($null -ne $found) { $source = "available on PSModulePath" }
        }

        if ($null -eq $found) {
            throw("{0} module not found. Install it with: Install-Module {0} -Scope CurrentUser - or, if you keep a copy outside PSModulePath, import it before running this script: Import-Module <path>\{0}.psd1" -f $module)
        }

        $minVersion = $preReqModules[$module]
        if ($null -ne $minVersion) {
            # Strip any prerelease suffix (e.g. 3.2.0-nightly) before comparing
            $foundVersion = [version](("$($found.Version)" -split '-')[0])
            if ($foundVersion -lt $minVersion) {
                throw("{0} version {1} is {2}, but version {3} or newer is required. Update it with: Update-Module {0}" -f $module, $found.Version, $source, $minVersion)
            }
        }

        Write-Host "  $module $($found.Version) - $source" -ForegroundColor DarkGray
    }
}

# Answers "does the target site exist?" without ever guessing.
#
# Get-PnPTenantSite fails BOTH for a site that does not exist and for a connection that
# may not read tenant site properties - a different account picked in the interactive
# browser sign-in, no SharePoint Administrator role in this tenant, or throttling. Read
# with -ErrorAction SilentlyContinue, the two are indistinguishable: both yield $null.
# That is how a run against an EXISTING installation enters the creation path and, two
# prompts later, offers to permanently delete the customer's Microsoft 365 group AND its
# site. So classify the failure instead: only a genuine not-found means "the URL is free".
#
# Returns 'Exists', 'NotFound' or 'Unknown' - the reason for 'Unknown' is left in
# $script:siteLookupError.
function GetSiteExistenceState([string]$Url) {
    $script:siteLookupError = $null
    try {
        $existing = Get-PnPTenantSite -Url $Url -ErrorAction Stop
        if ($null -ne $existing) { return 'Exists' }
        return 'NotFound'
    }
    catch {
        $message = "$($_.Exception.Message)"
        # SPO reports a missing site as "File Not Found" / "Cannot get site ..." - safe to
        # read as "the URL is free", as are the other unambiguous not-found phrasings.
        # Anything else (401/403, access denied, throttling) means the lookup did not answer
        # the question, and must not be read as an answer. Erring towards 'Unknown' only
        # stops the run; erring towards 'NotFound' is what put a customer site one keypress
        # from deletion.
        if ($message -match '(?i)file not found|cannot get site|could not be found|does not exist|404') {
            return 'NotFound'
        }
        $script:siteLookupError = ($message -split "`r?`n")[0]
        return 'Unknown'
    }
}

# Create site and apply provisioning template
function CreateRequestsSharePointSite {
    try {
        Write-Host "### BESTILLINGSPORTALEN SPO SITE CREATION ###`nCreating Bestillingsportalen SharePoint site..." -ForegroundColor Yellow

        $siteState = GetSiteExistenceState $requestsSiteUrl
        if ($siteState -eq 'Unknown') {
            throw "Could not determine whether $requestsSiteUrl already exists - the tenant site lookup failed with: $script:siteLookupError. Nothing has been changed. This is almost always the account: the PnP sign-in must be a SharePoint Administrator in THIS tenant (see 'Signed in as (PnP)' in the pre-flight summary). PnP.PowerShell caches the account on disk, so -Interactive may have signed you in silently as an account from another tenant - see the pre-flight checklist for the command that clears it. The run stops here on purpose: an unanswered lookup would be treated as 'no site here' and send the deployment into creating a new one."
        }
        $site = if ($siteState -eq 'Exists') { $true } else { $null }

        if (!$site) {
            $purgePerformed = $false

            # A soft-deleted site with the same URL blocks creation - New-PnPSite hangs
            # and eventually dies with an opaque NullReferenceException. Detect it and
            # offer to purge it from the tenant recycle bin.
            $deletedSite = Get-PnPTenantDeletedSite -Identity $requestsSiteUrl -ErrorAction SilentlyContinue
            if ($null -ne $deletedSite) {
                Write-Host "A deleted site with URL $requestsSiteUrl is in the tenant recycle bin - it blocks creating a new site on the same URL." -ForegroundColor Yellow
                if ($Force) {
                    throw "The site URL $requestsSiteUrl is occupied by a deleted site in the tenant recycle bin. Purging it is irreversible, so -Force will not do it: re-run without -Force to decide interactively, purge it yourself (Remove-PnPTenantDeletedSite), or choose a different requestsSiteName."
                }
                $purge = Read-Host "Permanently delete it from the recycle bin and continue? ( y / n = abort )"
                if ($purge -ne 'y') {
                    throw "The site URL is occupied by a deleted site in the tenant recycle bin. Permanently delete it (Remove-PnPTenantDeletedSite) or choose a different requestsSiteName, then re-run."
                }
                Write-Host "Permanently deleting the site from the tenant recycle bin..." -ForegroundColor Yellow
                Remove-PnPTenantDeletedSite -Identity $requestsSiteUrl -Force | Out-Null
                Write-Host "Deleted." -ForegroundColor Green
                $purgePerformed = $true
            }

            # A soft-deleted M365 group with the same alias also blocks reuse - the
            # mailNickname stays reserved until the group is permanently deleted from
            # Entra ID (30-day retention). Best-effort check via Graph.
            $deletedGroupJson = az rest --method get --url "https://graph.microsoft.com/v1.0/directory/deletedItems/microsoft.graph.group?`$filter=mailNickname eq '$requestsSiteAlias'&`$count=true" --headers "ConsistencyLevel=eventual" 2>$null
            $deletedGroup = if ($deletedGroupJson) { @(($deletedGroupJson | ConvertFrom-Json).value) | Select-Object -First 1 } else { $null }
            if ($null -ne $deletedGroup) {
                Write-Host "A deleted Microsoft 365 group with alias '$requestsSiteAlias' ('$($deletedGroup.displayName)') exists in Entra ID - the alias stays reserved until the group is permanently deleted." -ForegroundColor Yellow
                if ($Force) {
                    throw "The group alias '$requestsSiteAlias' is reserved by a soft-deleted Microsoft 365 group ('$($deletedGroup.displayName)'). Permanently deleting it is irreversible, so -Force will not do it: re-run without -Force to decide interactively, delete it yourself (Entra ID -> Groups -> Deleted groups), or choose a different requestsSiteName."
                }
                $purgeGroup = Read-Host "Permanently delete the group and continue? ( y / n = abort )"
                if ($purgeGroup -ne 'y') {
                    throw "The group alias '$requestsSiteAlias' is reserved by a soft-deleted Microsoft 365 group. Permanently delete it (Entra ID -> Groups -> Deleted groups) or choose a different requestsSiteName, then re-run."
                }
                Write-Host "Permanently deleting the group from Entra ID..." -ForegroundColor Yellow
                az rest --method delete --url "https://graph.microsoft.com/v1.0/directory/deletedItems/$($deletedGroup.id)"
                if ($LASTEXITCODE -ne 0) {
                    throw "Could not permanently delete the soft-deleted group '$($deletedGroup.displayName)' ($($deletedGroup.id)). Delete it manually in Entra ID -> Groups -> Deleted groups, then re-run."
                }
                Write-Host "Deleted." -ForegroundColor Green
                $purgePerformed = $true
            }

            # An ACTIVE M365 group with the same alias also blocks creation. This is
            # typically debris from a previous partially failed site-creation attempt:
            # the group got created, but because the URL was blocked at the time, its
            # site ended up on a different URL (e.g. .../Bestillingsportalen2) - and
            # the cmdlet then crashed, leaving the group behind.
            $activeGroupJson = az rest --method get --url "https://graph.microsoft.com/v1.0/groups?`$filter=mailNickname eq '$requestsSiteAlias'" 2>$null
            $activeGroup = if ($activeGroupJson) { @(($activeGroupJson | ConvertFrom-Json).value) | Select-Object -First 1 } else { $null }
            if ($null -ne $activeGroup) {
                $groupSiteUrl = 'unknown'
                $groupSiteJson = az rest --method get --url "https://graph.microsoft.com/v1.0/groups/$($activeGroup.id)/sites/root?`$select=webUrl" 2>$null
                if ($groupSiteJson) { $groupSiteUrl = ($groupSiteJson | ConvertFrom-Json).webUrl }

                # Second line of defence, over Graph rather than the SPO admin API: if the
                # group owns EXACTLY the site this run targets, it is not debris from a
                # failed attempt - it is the installation we are upgrading, and the site
                # lookup above was wrong about it. Never offer to delete that.
                if ("$groupSiteUrl".TrimEnd('/') -ieq "$requestsSiteUrl".TrimEnd('/')) {
                    throw "The Microsoft 365 group '$($activeGroup.displayName)' already owns exactly the site this run targets ($requestsSiteUrl) - that is the existing installation, not left-over debris, so nothing will be deleted. The tenant site lookup did not see the site, which points at the account used for the PnP browser sign-in: it must be a SharePoint Administrator in THIS tenant. Sign in with the right account and re-run - the deployment then offers to apply the template to the existing site instead."
                }

                # And refuse to offer the deletion at all when we could not establish WHICH
                # site the group owns: 'unknown' means the Graph lookup failed, not that the
                # group is harmless. Offering to delete a group whose site we cannot identify
                # is the same gamble in a different disguise.
                if ($groupSiteUrl -eq 'unknown') {
                    throw "An ACTIVE Microsoft 365 group with alias '$requestsSiteAlias' ('$($activeGroup.displayName)', created $($activeGroup.createdDateTime)) holds the alias, but its site could not be read over Graph - so there is no way to tell from here whether it is debris from a failed attempt or an installation in use. Nothing will be deleted. Check the group and its site manually (M365 admin -> Groups), then either delete it yourself or set requestsSiteAlias in $parametersFileName to a free alias, and re-run."
                }

                Write-Host "An ACTIVE Microsoft 365 group with alias '$requestsSiteAlias' already exists: '$($activeGroup.displayName)', created $($activeGroup.createdDateTime), site: $groupSiteUrl." -ForegroundColor Yellow
                Write-Host "This is typically left behind by a previous partially failed site-creation attempt (the site ended up on a different URL). Check that the group/site contains nothing of value before deleting." -ForegroundColor Yellow
                if ($Force) {
                    throw "The group alias '$requestsSiteAlias' is in use by an ACTIVE Microsoft 365 group ('$($activeGroup.displayName)', site: $groupSiteUrl). Deleting it would take its site with it, so -Force will not do it: verify the group holds nothing of value, then re-run without -Force to confirm - or choose a different requestsSiteName."
                }
                $deleteGroup = Read-Host "PERMANENTLY delete this group (including its site) and continue? ( y / n = abort )"
                if ($deleteGroup -ne 'y') {
                    throw "The group alias '$requestsSiteAlias' is in use by an existing Microsoft 365 group ('$($activeGroup.displayName)', site: $groupSiteUrl). Delete it or choose a different requestsSiteName, then re-run."
                }

                Write-Host "Deleting the group..." -ForegroundColor Yellow
                az rest --method delete --url "https://graph.microsoft.com/v1.0/groups/$($activeGroup.id)"
                if ($LASTEXITCODE -ne 0) {
                    throw "Could not delete the group '$($activeGroup.displayName)' ($($activeGroup.id)). Delete it manually (M365 admin -> Groups), then re-run."
                }

                # The delete above is a soft delete - purge it from deleted items too so
                # the alias is actually released. The soft delete needs a moment to
                # propagate, so retry the purge a few times.
                $groupPurged = $false
                for ($purgeAttempt = 1; $purgeAttempt -le 5; $purgeAttempt++) {
                    Start-Sleep -Seconds 10
                    az rest --method delete --url "https://graph.microsoft.com/v1.0/directory/deletedItems/$($activeGroup.id)" 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        $groupPurged = $true
                        break
                    }
                }
                if ($groupPurged) {
                    Write-Host "Group deleted and purged - the alias is being released." -ForegroundColor Green
                }
                else {
                    Write-Host "Group deleted, but the permanent purge has not gone through yet - if site creation below fails, re-run the script (the soft-deleted group check will offer the purge again)." -ForegroundColor Yellow
                }
                $purgePerformed = $true
            }

            # Permanent deletion of a site/group propagates asynchronously in SPO and
            # Entra ID. Until the URL is fully released, site creation fails with
            # "404 FILE NOT FOUND" - even when the site is gone from both the recycle
            # bin and the active site list. This normally clears in minutes but can in
            # the worst case take hours. Retry 404s with backoff before giving up;
            # other errors (naming policy etc.) fail immediately.
            $maxAttempts = 8
            for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                try {
                    Write-Host "Creating the site (group-connected site provisioning is synchronous and can take several minutes - the command returns when SharePoint reports the site ready)..." -ForegroundColor Yellow
                    # Deliberately NO -Owners here. Passing the service account as the only
                    # owner leaves the CALLING user (the installing admin) without any
                    # access to the new site - group-connected sites grant access solely
                    # through group membership - and New-PnPSite's readiness wait then
                    # hangs indefinitely: the site shows up in the admin center while the
                    # cmdlet never returns. Creating without -Owners makes the caller
                    # group owner and member automatically, so the wait can complete. The
                    # service account is added as owner and member right after creation.
                    $createdSiteUrl = New-PnPSite -Type TeamSite -Title $parameters.requestsSiteName.Value -Alias $requestsSiteAlias -Description $parameters.requestsSiteDesc.Value

                    # Trust what SharePoint created, not what we asked for. If the alias is
                    # taken, SharePoint appends a number instead of failing - so the site
                    # ends up somewhere other than the URL computed above, and every later
                    # step addressing the expected URL fails with an unhelpful null
                    # reference. ValidateSiteAlias catches the collision we know about
                    # (the service account); this catches the rest - naming policies,
                    # blocked words, or any other object holding the alias.
                    $createdSiteUrl = "$createdSiteUrl".Trim()
                    if (-not [string]::IsNullOrWhiteSpace($createdSiteUrl) -and $createdSiteUrl -ine $requestsSiteUrl) {
                        Write-Host "WARN: SharePoint created the site at $createdSiteUrl, not the requested $requestsSiteUrl - the alias '$requestsSiteAlias' was not available." -ForegroundColor Yellow
                        Write-Host "      Continuing against the URL SharePoint actually created. To get the intended URL instead, delete this site and its group, set requestsSiteAlias in $parametersFileName to a free alias, and re-run." -ForegroundColor Yellow
                        $script:requestsSiteUrl = $createdSiteUrl
                        $script:requestsSiteAlias = ($createdSiteUrl -split '/')[-1]
                    }
                    break
                }
                catch {
                    $transient = $purgePerformed -or $_.Exception.Message -match '404'
                    if (-not $transient) { throw }
                    if ($attempt -eq $maxAttempts) {
                        throw "Site creation still fails with '$($_.Exception.Message)' after $maxAttempts attempts. If a site on this URL was recently (permanently) deleted, SharePoint may still be releasing the URL - this can take from minutes up to several hours. Wait and re-run, or use a different requestsSiteName."
                    }
                    Write-Host "Site creation attempt $attempt/$maxAttempts failed ($($_.Exception.Message)) - the URL is probably still being released after a deletion. Retrying in 60 seconds..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 60
                }
            }
        
            Write-Host "Waiting for site to finish creating..." -ForegroundColor Yellow
            
            Start-sleep -Seconds 60
            Write-Host "Site created`n**BESTILLINGSPORTALEN SITE CREATION COMPLETE**" -ForegroundColor Green

            # The service account was intentionally not the -Owners of New-PnPSite (see
            # the comment above the call) - it is put in place here instead, as both
            # OWNER and MEMBER: owner does not imply member in Microsoft 365 groups, and
            # the approval flow and Teams welcome message run as this account and need
            # actual access. Done with az (the CLI session is the installing admin) so it
            # works regardless of the PnP app's delegated Graph permissions.
            Write-Host "Adding the service account as group owner and member..." -ForegroundColor Yellow
            try {
                $saObjectId = az ad user show --id $parameters.serviceAccountUPN.Value --query id --output tsv
                if ([string]::IsNullOrWhiteSpace($saObjectId)) { throw "could not resolve the service account's object id" }

                # The group is seconds old - give the directory a few tries to show it.
                $groupId = $null
                for ($lookupAttempt = 1; $lookupAttempt -le 5; $lookupAttempt++) {
                    $groupJson = az rest --method get --url "https://graph.microsoft.com/v1.0/groups?`$filter=mailNickname eq '$requestsSiteAlias'&`$select=id" 2>$null
                    $groupId = if ($groupJson) { @(($groupJson | ConvertFrom-Json).value) | Select-Object -First 1 -ExpandProperty id } else { $null }
                    if ($groupId) { break }
                    Start-Sleep -Seconds 15
                }
                if (-not $groupId) { throw "the Microsoft 365 group with alias '$requestsSiteAlias' did not show up in the directory" }

                # Idempotent: adding an existing owner/member is an error, so check first.
                $ownersJson = az rest --method get --url "https://graph.microsoft.com/v1.0/groups/$groupId/owners?`$select=id" 2>$null
                $existingOwners = if ($ownersJson) { @(($ownersJson | ConvertFrom-Json).value.id) } else { @() }
                if ($existingOwners -notcontains $saObjectId) {
                    az ad group owner add --group $groupId --owner-object-id $saObjectId --output none
                    if ($LASTEXITCODE -ne 0) { throw "az ad group owner add failed - see the error above" }
                }
                $isMember = az ad group member check --group $groupId --member-id $saObjectId --query value --output tsv 2>$null
                if ($isMember -ne 'true') {
                    az ad group member add --group $groupId --member-id $saObjectId --output none
                    if ($LASTEXITCODE -ne 0) { throw "az ad group member add failed - see the error above" }
                }
                Write-Host "Service account added as group owner and member." -ForegroundColor Green
            }
            catch {
                Write-Host "WARN: Could not add the service account as group owner/member ($(($_.Exception.Message -split "`r?`n")[0]))." -ForegroundColor Yellow
                Write-Host "      Add $($parameters.serviceAccountUPN.Value) manually as OWNER and MEMBER of the '$($parameters.requestsSiteName.Value)' Microsoft 365 group (Entra ID or the site's group membership) - the approval flow and the Teams welcome message run as this account and need the access." -ForegroundColor Yellow
            }
        }
        else {
            # -Force answers this with NO on purpose: an unattended run should never
            # change the site's schema as a side effect. Use -Upgrade, or answer
            # interactively, when a template update is actually intended.
            #
            # Note the template's DataRows all use UpdateBehavior="Skip" - applying it
            # NEVER resets existing list items. It updates schema/views and adds
            # missing default rows. The prompt used to threaten a config-list reset,
            # which stopped being true with the DataRows migration.
            if ($Force) {
                $global:skipApplyTemplate = $true
                Write-Host "Site already exists. -Force: NOT re-applying the PnP template. Continuing with the rest of the deploy..." -ForegroundColor Yellow
            }
            else {
                Write-Host "Site already exists. Apply the PnP provisioning template to it?" -ForegroundColor Yellow
                if ($global:upgrade) {
                    Write-Host "  y = apply the latest template (schema, views, new lists). Existing list items and navigation are preserved; missing default rows are added." -ForegroundColor Cyan
                    Write-Host "  n = skip the template entirely (only reads the list ids), then continue with the rest of the upgrade. Tip: -SkipSharepointSite skips this whole step including the prompt." -ForegroundColor Cyan
                }
                else {
                    Write-Host "  y = re-apply the template and re-run the site configuration. Existing list items are preserved (missing default rows are added); request data is never touched." -ForegroundColor Cyan
                    Write-Host "  n = leave the site untouched (only reads the list ids), then continue with Logic Apps / SPFx / other deploy steps" -ForegroundColor Cyan
                }
                $overwrite = Read-Host " ( y / n )"
                if ($overwrite -ne "y") {
                    $global:skipApplyTemplate = $true
                    Write-Host "Skipping the template. Continuing with the rest of the deploy..." -ForegroundColor Yellow
                }
            }
        }

        # On a fresh creation the installing user is already group owner (New-PnPSite
        # without -Owners), but grant site collection admin explicitly anyway: it also
        # covers re-runs against a site created by an OLDER version of this script,
        # where the service account was the only group owner and the installing admin
        # had no access at all. Works via the tenant admin connection without site
        # access, and is additive - it does not remove existing admins.
        if (-not [string]::IsNullOrEmpty($deployUser)) {
            Write-Host "Granting the installing user ($deployUser) site collection admin on the site..." -ForegroundColor Yellow
            # Convenience, not a requirement - and it can legitimately fail: $deployUser
            # comes from the Azure CLI session, which for a consultant is often a GUEST in
            # the customer tenant (the Az, CLI and PnP sign-ins are three separate
            # identities and need not be the same account). A failure here must not take
            # the whole site step - and with it the deployment - down with it.
            try {
                Set-PnPTenantSite -Identity $requestsSiteUrl -Owners $deployUser -ErrorAction Stop
            }
            catch {
                Write-Host "WARN: Could not grant $deployUser site collection admin ($(($_.Exception.Message -split "`r?`n")[0]))." -ForegroundColor Yellow
                Write-Host "      Continuing. If a later step fails with access denied, grant the account running this script site collection admin on $requestsSiteUrl via the SharePoint admin center and re-run." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "WARN: Could not determine the installing user (az ad signed-in-user failed) - if the next step fails with access denied, grant yourself site collection admin on $requestsSiteUrl via the SharePoint admin center and re-run." -ForegroundColor Yellow
        }
    }
    catch {
        RecordDeployStatus -Component "SharePoint site + PnP template" -Status 'FAILED' -Detail $_.Exception.Message
        # 'throw(a, b)' throws a two-element array - the message reached the console with
        # a literal {0} in it. -f actually formats.
        throw ("Failed to create the SharePoint site: {0}" -f $_.Exception.Message)
    }
}

# Configure the new site
function ConfigureSharePointSite {

    try {

        Write-Host "### BESTILLINGSPORTALEN SPO SITE CONFIGURATION ###`nConfiguring SharePoint site..." -ForegroundColor Yellow

        If ($parameters.skipApplySPOTemplate.Value -or $global:skipApplyTemplate) {

            Write-Host "Skipping provisioning template apply" -ForegroundColor Yellow
        }
        else {

            Write-Host "Applying provisioning template..." -ForegroundColor Yellow

            # Default list items are seeded by the <pnp:DataRows> blocks in the template
            # (KeyColumn + UpdateBehavior="Skip"): existing items are never modified,
            # missing default items are added. SPOManagedPath is the only template parameter.
            $templateParameters = @{ SPOManagedPath = $parameters.managedPath.Value }

            if ($global:upgrade) {
                # Preserve existing navigation in upgrade mode - apply schema/settings only
                Invoke-PnPSiteTemplate -Path (Join-Path $packageRootPath $templatePath) -Parameters $templateParameters
            }
            else {
                Invoke-PnPSiteTemplate -Path (Join-Path $packageRootPath $templatePath) -ClearNavigation -Parameters $templateParameters
            }

            Write-Host "Applied template" -ForegroundColor Green
        }

        # In upgrade mode (or when the user chose to keep the existing site content) the
        # remaining site configuration below (field renames, folder recreation, form
        # visibility tweaks) was already done at install time and is skipped. List item
        # seeding happens inside the template apply above and only adds missing default
        # rows - existing items are never touched. List ids are still collected - they
        # are needed for the Logic App deployments.
        if ($global:upgrade -or $global:skipApplyTemplate) {
            if ($global:upgrade) {
                Write-Host "Running in Upgrade Mode - skipping site configuration (list items: existing preserved, missing defaults added by the template)" -ForegroundColor Yellow
                Write-Host "For more information, see Upgrade.md" -ForegroundColor Cyan
            }
            else {
                Write-Host "Keeping existing site content - skipping site configuration (only collecting list ids)" -ForegroundColor Yellow
            }

            # Still need to get list IDs for logic app deployment
            $context = Get-PnPContext
            $web = $context.Web
            $context.Load($web)
            $context.Load($web.Lists)
            $t = $web.Lists.EnsureSiteAssetsLibrary()
            $context.ExecuteQuery()
            
            $siteRequestsList = Get-PnPList $requestsListName
            $context.Load($siteRequestsList)
            $context.ExecuteQuery()
            $global:requestsListId = $siteRequestsList.Id
            
            $siteRequestsSettingsList = Get-PnPList $requestSettingsListName
            $context.Load($siteRequestsSettingsList)
            $context.ExecuteQuery()
            $global:requestsSettingsListId = $siteRequestsSettingsList.Id
            
            $siteTemplatesList = Get-PnPList $siteTemplatesListName
            $context.Load($siteTemplatesList)
            $context.ExecuteQuery()
            $global:siteTemplatesListId = $siteTemplatesList.Id
            
            $hubSitesList = Get-PnPList $hubSitesListName
            $context.Load($hubSitesList)
            $context.ExecuteQuery()
            $global:hubSitesListId = $hubSitesList.Id
            
            $teamsTemplatesList = Get-PnPList $teamsTemplatesListName
            $context.Load($teamsTemplatesList)
            $context.ExecuteQuery()
            $global:teamsTemplatesListId = $teamsTemplatesList.Id
            
            $ipLabelsList = Get-PnPList $ipLabelsListName
            $context.Load($ipLabelsList)
            $context.ExecuteQuery()
            $global:ipLabelsListId = $ipLabelsList.Id

            $guestRequestsList = Get-PnPList $guestRequestsListName
            $context.Load($guestRequestsList)
            $context.ExecuteQuery()
            $global:guestRequestsListId = $guestRequestsList.Id

            Write-Host "Finished site configuration (existing list content preserved)" -ForegroundColor Green
            return
        }
        
            
        $context = Get-PnPContext
        # Ensure Site Assets
        $web = $context.Web
        $context.Load($web)
        $context.Load($web.Lists)
        $t = $web.Lists.EnsureSiteAssetsLibrary()
        $context.ExecuteQuery()
        
        Write-Host "Site Assets library initialised" -ForegroundColor Green

        # Rename Title field
        $siteRequestsList = Get-PnPList $requestsListName
        $context.Load($siteRequestsList)
        $context.ExecuteQuery()

        $context.Load($siteRequestsList.Fields)
        $context.ExecuteQuery()

        $global:requestsListId = $siteRequestsList.Id
        $fields = $siteRequestsList.Fields

        $titleField = $fields | Where-Object { $_.InternalName -eq $TitleFieldName }
        $titleField.Title = $SpaceTitleFieldName
        $titleField.UpdateAndPushChanges($true)
        $context.ExecuteQuery()

        # Site Assets folders: create what is missing, touch nothing that exists.
        #
        # This used to DELETE the whole 'Provisioning Request' folder and recreate it
        # whenever it was already there. On a re-deploy or an upgrade that threw away every
        # image and icon the customer had uploaded for their own provisioning types, and
        # left the Image/Icon URLs on those list items pointing at deleted files. Nothing
        # needed the reset: UploadAssets writes the package's own files by name and
        # overwrites them either way. Resolve-PnPFolder returns the folder and creates it
        # only if it does not exist, which is the whole requirement.
        Resolve-PnPFolder -SiteRelativePath "$siteAssetsListURL/$provRequestsFolderName" | Out-Null
        Resolve-PnPFolder -SiteRelativePath $imageFolderUpload | Out-Null
        Resolve-PnPFolder -SiteRelativePath $iconFolderUpload | Out-Null

        Write-Host "Site Assets folders in place (existing uploads preserved)" -ForegroundColor Green

        # Adding settings in Site request Settings list
        $siteRequestsSettingsList = Get-PnPList $requestSettingsListName
        $context.Load($siteRequestsSettingsList)
        $context.ExecuteQuery()

        # Get request settings list id
        $global:requestsSettingsListId = $siteRequestsSettingsList.Id

        # Get site templates List id
        $siteTemplatesList = Get-PnPList $siteTemplatesListName
        $context.Load($siteTemplatesList)
        $context.ExecuteQuery()

        $global:siteTemplatesListId = $siteTemplatesList.Id

        # Get hub sites List id
        $hubSitesList = Get-PnPList $hubSitesListName
        $context.Load($hubSitesList)
        $context.ExecuteQuery()

        $global:hubSitesListId = $hubSitesList.Id

        # Default settings items are seeded by the <pnp:DataRows> block in the template.
        # Sensitivity labels are enabled by flipping EnableSensitivityLabels in the
        # 'Provisioning Request Settings' list after install - there is no install-time
        # parameter for it. Nothing is conditionally deployed: the SyncLabels logic app,
        # the IP Labels list and InformationProtectionPolicy.Read.All are always in
        # place, so the list item is the only switch. See Sensitivity-labels.md.

        # Hide blocked words field in settings list
        $field = $siteRequestsSettingsList.Fields.GetByInternalNameOrTitle("BlockedWordsValue")
        $field.SetShowInEditForm($false)
        $context.ExecuteQuery()
        $field.SetShowInNewForm($false)
        $context.ExecuteQuery()
        $field.SetShowInDisplayForm($false)
        $context.ExecuteQuery()

        Write-Host "Configured Provisioning Request Settings list" -ForegroundColor Green

        # Configure the Provisioning Types list (items are seeded by the template)
        $provTypesList = Get-PnPList $provTypesListName
        $context.Load($provTypesList)
        $context.ExecuteQuery()

        #Hide internal title field in provisioning types list
        $field = $provTypesList.Fields.GetByInternalNameOrTitle("InternalTitle")
        $field.SetShowInEditForm($false)
        $context.ExecuteQuery()
        $field.SetShowInNewForm($false)
        $context.ExecuteQuery()
        $field.SetShowInDisplayForm($false)
        $context.ExecuteQuery()

        Write-Host "Configured Provisioning Types list" -ForegroundColor Green

        # Get id of the Teams Templates list (items are seeded by the template)
        $teamsTemplatesList = Get-PnPList $teamsTemplatesListName
        $context.Load($teamsTemplatesList)
        $context.ExecuteQuery()

        $global:teamsTemplatesListId = $teamsTemplatesList.Id

        # Hide site template store field - site templates list
        $field = Get-PnPField -Identity "Store" -List "Site Templates"

        $field.SetShowInEditForm($false)
        $field.SetShowInNewForm($false)
        $field.SetShowInDisplayForm($false)
        $context.ExecuteQuery()

        # Hide site template store field - provisioning requests list
        $field = Get-PnPField -Identity "SiteTemplateStore" -List "Provisioning Requests"

        $field.SetShowInEditForm($false)
        $field.SetShowInNewForm($false)
        $field.SetShowInDisplayForm($false)
        $context.ExecuteQuery()

        # Hide space type internal field - provisioning requests list
        $field = Get-PnPField -Identity "SpaceTypeInternal" -List "Provisioning Requests"

        $field.SetShowInEditForm($false)
        $field.SetShowInNewForm($false)
        $field.SetShowInDisplayForm($false)
        $context.ExecuteQuery()

        # Get id of the ip labels list
        $ipLabelsList = Get-PnPList $ipLabelsListName
        $context.Load($ipLabelsList)
        $context.ExecuteQuery()
        $global:ipLabelsListId = $ipLabelsList.Id

        # Get id of the guest requests list
        $guestRequestsList = Get-PnPList $guestRequestsListName
        $context.Load($guestRequestsList)
        $context.ExecuteQuery()
        $global:guestRequestsListId = $guestRequestsList.Id

        Write-Host "Configuring Service Account permissions"
        Add-PnPSiteCollectionAdmin -Owners $parameters.serviceAccountUPN.value

        Write-Host "Finished configuring site" -ForegroundColor Green

    }
    catch {
        RecordDeployStatus -Component "SharePoint site + PnP template" -Status 'FAILED' -Detail $_.Exception.Message
        throw('Failed to configure the SharePoint site {0}', $_.Exception.Message)
    }
}

function UploadFiles ($targetFolder, $sourcePath, $sourceFolder, $libraryName) {
    # Upload files into the folder
    $files = Get-ChildItem (Join-Path $sourcePath $sourceFolder)
    foreach ($file in $files) {
        Add-PnPFile -Path $file.FullName -Folder $targetFolder | Out-Null
    }
    Write-Host "Uploaded $($files.Count) files from $sourceFolder to $libraryName" -ForegroundColor Green
}


# Upload assets - Provisioning Type images to the Site Assets library
function UploadAssets {
    try {
        Write-Host "Uploading assets" -ForegroundColor Yellow

        UploadFiles  $imageFolderUpload $packageRootPath $imagesDir "Site Assets"
        UploadFiles  $iconFolderUpload $packageRootPath $iconsDir "Site Assets"

        Write-Host "**BESTILLINGSPORTALEN SPO SITE CONFIGURATION COMPLETE**" -ForegroundColor Green
    }
    catch {
        RecordDeployStatus -Component "SharePoint site + PnP template" -Status 'FAILED' -Detail $_.Exception.Message
        throw('Failed to upload assets {0}', $_.Exception.Message)
    }
}

# ---------------------------------------------------------------------------
# Deployment report
# Each major component records its outcome here and WriteDeploymentReport prints
# a summary at the end of the run (also when the script stops on an error), so
# partial failures don't drown in the console output.
# ---------------------------------------------------------------------------
$script:deployReport = @()
$script:deployReportPrinted = $false

function RecordDeployStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Component,
        [Parameter(Mandatory = $true)][ValidateSet('OK', 'FAILED', 'WARNING', 'SKIPPED')][string]$Status,
        [string]$Detail = ""
    )
    $script:deployReport += [pscustomobject]@{ Component = $Component; Status = $Status; Detail = $Detail }
}

# Records the result of the preceding az CLI call. Native commands do not throw on
# non-zero exit codes, so without this a failed deployment scrolls past unnoticed
# and the script reports success.
function RecordAzResult {
    param(
        [Parameter(Mandatory = $true)][string]$Component,
        # Name of the ARM deployment behind the az call (defaults to the template
        # file's base name when az deployment group create is run without --name).
        # When set, a failure fetches the REAL error from the deployment record:
        # the CLI's own output is sometimes useless - notably 'The content for this
        # response was already consumed', a known CLI bug where the error response
        # body is read once internally and lost before it can be shown.
        [string]$DeploymentName
    )
    # Captured FIRST and restored at the end: the az calls below overwrite
    # $LASTEXITCODE, and callers check it AFTER this function to decide whether to
    # abort - without the restore, a failed deployment would look successful.
    $azExitCode = $LASTEXITCODE

    if ($azExitCode -ne 0) {
        $detail = "az exited with code $azExitCode - see the error output above"
        if ($DeploymentName) {
            try {
                $armErrorJson = az deployment group show --resource-group $parameters.resourceGroupName.Value --name $DeploymentName --query 'properties.error' --output json 2>$null
                if ($armErrorJson -and $armErrorJson -ne 'null') {
                    Write-Host "ARM error for deployment '$DeploymentName' (fetched from the deployment record - the CLI output above may have swallowed it):" -ForegroundColor Red
                    Write-Host $armErrorJson -ForegroundColor Red
                    $detail = "ARM error: $(("$armErrorJson" -replace '\s+', ' ').Trim())"
                }
                # The per-resource operations usually carry the most specific message
                # (policy denials, quota, provider registration).
                $opErrorsJson = az deployment operation group list --resource-group $parameters.resourceGroupName.Value --name $DeploymentName --query "[?properties.provisioningState=='Failed'].{resource:properties.targetResource.resourceName, code:properties.statusMessage.error.code, message:properties.statusMessage.error.message}" --output json 2>$null
                $opErrors = if ($opErrorsJson) { @($opErrorsJson | ConvertFrom-Json) } else { @() }
                foreach ($op in $opErrors) {
                    Write-Host ("  Failed resource: {0} [{1}] {2}" -f $op.resource, $op.code, $op.message) -ForegroundColor Red
                }
                if ($opErrors.Count -gt 0) {
                    $detail = "$detail | " + (@($opErrors | ForEach-Object { "$($_.resource): [$($_.code)] $($_.message)" }) -join ' | ')
                }
            }
            catch {}
        }
        RecordDeployStatus -Component $Component -Status 'FAILED' -Detail $detail
        Write-Host "$Component FAILED - continuing with the remaining components. See the summary at the end." -ForegroundColor Red
    }
    else {
        RecordDeployStatus -Component $Component -Status 'OK'
    }

    $global:LASTEXITCODE = $azExitCode
}

function GetFailedDeployComponents {
    return @($script:deployReport | Where-Object { $_.Status -eq 'FAILED' })
}

function WriteDeploymentReport {
    if ($script:deployReportPrinted -or $script:deployReport.Count -eq 0) { return }
    $script:deployReportPrinted = $true

    Write-Host ""
    Write-Host "#################### DEPLOYMENT SUMMARY ####################" -ForegroundColor Magenta
    foreach ($entry in $script:deployReport) {
        $color = switch ($entry.Status) {
            'OK' { 'Green' }
            'FAILED' { 'Red' }
            'WARNING' { 'Yellow' }
            'SKIPPED' { 'DarkGray' }
        }
        $line = "  [{0,-7}] {1}" -f $entry.Status, $entry.Component
        if (-not [string]::IsNullOrEmpty($entry.Detail)) { $line += " - $($entry.Detail)" }
        Write-Host $line -ForegroundColor $color
    }

    $failed = GetFailedDeployComponents
    $warned = @($script:deployReport | Where-Object { $_.Status -eq 'WARNING' })
    Write-Host ""
    if ($failed.Count -gt 0) {
        Write-Host "$($failed.Count) component(s) FAILED. Fix the cause and re-run the script - completed components are updated idempotently on re-run." -ForegroundColor Red
    }
    elseif ($warned.Count -gt 0) {
        Write-Host "Completed with $($warned.Count) warning(s) - review them before using the solution." -ForegroundColor Yellow
    }
    else {
        Write-Host "All components completed successfully." -ForegroundColor Green
    }
    Write-Host "############################################################" -ForegroundColor Magenta
}

# ---------------------------------------------------------------------------
# ARM template validation
#
# az CLI parses --template-file with Python's json module, which rejects trailing
# commas. PowerShell's ConvertFrom-Json accepts them, so "it parsed fine locally" is
# not proof - and az only reports "Failed to parse '<file>', please check whether it
# is a valid JSON format" with no line number, which is painful in a 5000-line
# template.
#
# System.Text.Json is strict about trailing commas by default and reports line and
# position, so this catches the same class of error az would, but usefully. Runs
# before anything is created.
# ---------------------------------------------------------------------------
function ValidateArmTemplates {
    $templateDir = Join-Path $packageRootPath "ARMTemplates/LogicApps"
    $invalid = @()

    foreach ($template in (Get-ChildItem -Path $templateDir -Filter *.json -File)) {
        try {
            $json = Get-Content $template.FullName -Raw
            [System.Text.Json.JsonDocument]::Parse($json).Dispose()
        }
        catch {
            # System.Text.Json puts "LineNumber: N | BytePositionInLine: M" in the message
            Write-Host "  INVALID: $($template.Name) - $($_.Exception.Message)" -ForegroundColor Red
            $invalid += "$($template.Name): $($_.Exception.Message)"
            continue
        }
    }

    # The .bicep templates are compiled locally too. Two failure modes end in the same
    # place otherwise: az downloads the Bicep CLI on first use (blocked in some
    # proxy/firewall-restricted environments), and a compile error rejects the
    # deployment at submit - in both cases ARM never records a deployment
    # (DeploymentNotFound afterwards), and older az versions swallow the message
    # entirely ('The content for this response was already consumed'). Catch it here,
    # in pre-flight, not after half an hour of site provisioning. Compile errors from
    # az land on stderr and are visible right above the throw.
    foreach ($bicepFile in @('azureresources.bicep', 'runbooks.bicep')) {
        $bicepPath = Join-Path (Join-Path $packageRootPath 'ARMTemplates') $bicepFile
        az bicep build --file $bicepPath --stdout | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  INVALID: $bicepFile - see the compiler output above" -ForegroundColor Red
            $invalid += "$bicepFile failed to compile (or the Bicep CLI could not be installed - check proxy/firewall and run 'az bicep install' manually)"
            continue
        }
    }

    if ($invalid.Count -gt 0) {
        RecordDeployStatus -Component "ARM template validation" -Status 'FAILED' -Detail ($invalid -join ' | ')
        RecordPreflightCheck -Name "ARM/bicep templates" -Status MISSING -Detail ($invalid -join ' | ') -Fix "Fix the files listed above and re-run. For JSON, trailing commas are the usual cause: PowerShell's ConvertFrom-Json accepts them, az does not."
        return
    }

    RecordDeployStatus -Component "ARM template validation" -Status 'OK'
    RecordPreflightCheck -Name "ARM/bicep templates" -Status OK -Detail "All Logic App templates parse, both bicep templates compile"
}

# ---------------------------------------------------------------------------
# Service account validation
# The service account is used as site owner (New-PnPSite -Owners), for the delegated
# API connections and as the identity that posts the Teams welcome message - but
# nothing creates it. Fail early with a clear message instead of crashing midway
# through site creation when the account doesn't exist.
# Note: it no longer needs MFA disabled - that was only the sensitivity label ROPC flow.
# ---------------------------------------------------------------------------
function ValidateServiceAccount {
    $upn = $parameters.serviceAccountUPN.Value
    $saUserJson = az ad user show --id $upn 2>$null
    $saUser = if ($saUserJson) { $saUserJson | ConvertFrom-Json } else { $null }
    if ($null -eq $saUser) {
        RecordDeployStatus -Component "Service account" -Status 'FAILED' -Detail "'$upn' was not found in the tenant"
        RecordPreflightCheck -Name "Service account" -Status MISSING -Detail "'$upn' was not found in the tenant" -Fix "Create the account (a standard user licensed for SharePoint, Exchange Online and Teams), or correct serviceAccountUPN in $parametersFileName."
        return
    }
    $script:serviceAccountDisplayName = $saUser.displayName
    $script:serviceAccountMailNickname = $saUser.mailNickname
    $script:serviceAccountUpnLocalPart = ($upn -split '@')[0]

    # Best-effort license check - warning only: the exact license requirements
    # are the customer's call.
    try {
        $licenseDetails = az rest --method get --url "https://graph.microsoft.com/v1.0/users/$upn/licenseDetails" 2>$null | ConvertFrom-Json
        $servicePlans = @($licenseDetails.value.servicePlans.servicePlanName)
        if ($servicePlans.Count -eq 0) {
            RecordDeployStatus -Component "Service account" -Status 'WARNING' -Detail "'$upn' exists but has no licenses assigned"
            RecordPreflightCheck -Name "Service account" -Status WARNING -Detail "'$upn' exists but has no licenses assigned" -Fix "Assign a license that includes SPO, Exchange Online, Teams and seeded Power Automate (E- and F-plans both qualify)."
            return
        }
        # The account must be able to own and activate the solution flow
        # (Configuration-guide.md step 2).
        # Seeded Power Automate from any Office 365 plan qualifies - INCLUDING frontline
        # F-plans (FLOW_O365_S1), which are verified working in a real customer tenant
        # (import + activation, August 2026). An earlier FlowNotOriginalAuthor failure
        # on an F-plan happened in a dev tenant and appears to have been environment-
        # specific. The only plan still treated as unusable is an unprovisioned viral
        # trial (FLOW_P2_VIRAL without _REAL).
        $flowPlans = @($servicePlans | Where-Object { $_ -match '^FLOW_' -and $_ -ne 'FLOW_P2_VIRAL' })
        if ($flowPlans.Count -eq 0) {
            $foundFlowPlans = @($servicePlans | Where-Object { $_ -match '^FLOW_' }) -join ', '
            if (-not $foundFlowPlans) { $foundFlowPlans = 'none' }
            RecordDeployStatus -Component "Service account" -Status 'WARNING' -Detail "'$upn' has no seeded Power Automate plan for the approval flow"
            RecordPreflightCheck -Name "Service account" -Status WARNING -Detail "'$upn' has no seeded Power Automate plan (found: $foundFlowPlans)" -Fix "Assign a license with seeded Power Automate (any E- or F-plan) before importing the approval flow (Configuration-guide.md step 2). Unprovisioned viral trials do not count."
            return
        }
    }
    catch {}

    RecordDeployStatus -Component "Service account" -Status 'OK'
    RecordPreflightCheck -Name "Service account" -Status OK -Detail "$($saUser.displayName) ($upn), licensed incl. Power Automate"
}

# ---------------------------------------------------------------------------
# Pre-deployment checklist
# Every pre-flight check records its result here instead of throwing on first
# failure, so ONE run shows everything that is missing - not one wall per run.
# ShowPreflightChecklist renders the list; a MISSING item stops the deployment
# (after all checks have run), a WARNING does not. -Preflight renders the list
# and exits without deploying.
# ---------------------------------------------------------------------------
$script:preflightChecks = @()

function RecordPreflightCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('OK', 'MISSING', 'WARNING', 'SKIPPED', 'UNKNOWN')][string]$Status,
        [string]$Detail = '',
        [string]$Fix = ''
    )
    $script:preflightChecks += [pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail; Fix = $Fix }
}

# Renders the checklist and returns the number of MISSING items.
function ShowPreflightChecklist {
    Write-Host ""
    Write-Host "#################### PRE-DEPLOYMENT CHECKLIST ####################" -ForegroundColor Magenta
    foreach ($check in $script:preflightChecks) {
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
            Write-Host "            Fix: $($check.Fix)" -ForegroundColor Cyan
        }
    }
    $missing = @($script:preflightChecks | Where-Object { $_.Status -eq 'MISSING' })
    $warnings = @($script:preflightChecks | Where-Object { $_.Status -in @('WARNING', 'UNKNOWN') })
    Write-Host ""
    Write-Host ("  {0} missing, {1} warning(s), {2} ok" -f $missing.Count, $warnings.Count, @($script:preflightChecks | Where-Object Status -eq 'OK').Count) -ForegroundColor $(if ($missing.Count -gt 0) { 'Red' } elseif ($warnings.Count -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "##################################################################" -ForegroundColor Magenta
    Write-Host ""
    return $missing.Count
}

# Wildcard matching as ARM does it: '*' and prefix wildcards in actions. Used by the
# RBAC and resource provider pre-flight checks.
function TestActionMatch([string[]]$patterns, [string]$action) {
    foreach ($pattern in $patterns) {
        $regex = '^' + [regex]::Escape($pattern).Replace('\*', '.*') + '$'
        if ($action -imatch $regex) { return $true }
    }
    return $false
}

# Returns whether the signed-in account's EFFECTIVE permissions at $Scope include
# $Action. $null when the permissions endpoint cannot be read - the caller decides
# whether unknown blocks or not.
function TestAzureAction([string]$Scope, [string]$Action) {
    try {
        $permsJson = az rest --method get --url "https://management.azure.com$Scope/providers/Microsoft.Authorization/permissions?api-version=2022-04-01" 2>$null
        if (-not $permsJson) { return $null }
        $perms = @(($permsJson | ConvertFrom-Json).value)
        foreach ($entry in $perms) {
            if ((TestActionMatch @($entry.actions) $Action) -and -not (TestActionMatch @($entry.notActions) $Action)) {
                return $true
            }
        }
        return $false
    }
    catch {
        return $null
    }
}

# Fails the deployment early when the deploying account cannot create RBAC role
# assignments. azureresources.bicep contains two Microsoft.Authorization/roleAssignments
# (Automation Job/Runbook Operator for the UAMI), and ARM authorizes those at SUBMIT:
# without roleAssignments/write the whole deployment is rejected synchronously, no
# deployment record is created, and azure-cli (verified on 2.77.0) swallows the 400
# body and prints only 'The content for this response was already consumed'. This
# check turns that dead end into a clear message before anything runs.
#
# Checked against the RG when it exists (rights may be granted there), else the
# subscription. The permissions endpoint returns the caller's effective actions.
function ValidateAzureRbac {
    # Only azureresources.bicep needs roleAssignments/write (ARM authorizes its two
    # RBAC role assignments at submit). Upgrade mode never deploys that template, and
    # -SkipBicepDeploy skips it explicitly - blocking those runs on a permission they
    # will not use would force Owner onto accounts that only need Contributor for
    # runbook and logic app updates.
    if ($SkipBicepDeploy -or $Upgrade) {
        RecordPreflightCheck -Name "RBAC: role assignment rights" -Status SKIPPED -Detail $(if ($Upgrade) { "Upgrade mode does not deploy azureresources.bicep - no role assignments are created" } else { "-SkipBicepDeploy" })
        return
    }

    $subId = $parameters.subscriptionId.Value
    $rgName = $parameters.resourceGroupName.Value
    $scope = "/subscriptions/$subId"
    $scopeLabel = "subscription $subId"
    try {
        az group show --name $rgName --subscription $subId --output none 2>$null
        if ($LASTEXITCODE -eq 0) {
            $scope = "/subscriptions/$subId/resourceGroups/$rgName"
            $scopeLabel = "resource group $rgName"
        }

        $hasWrite = TestAzureAction -Scope $scope -Action 'Microsoft.Authorization/roleAssignments/write'
        if ($null -eq $hasWrite) { throw "the permissions endpoint could not be read" }
    }
    catch {
        # A failed CHECK must not block a deployment that might work - only a
        # confirmed missing permission should.
        RecordPreflightCheck -Name "RBAC: role assignment rights" -Status UNKNOWN -Detail "Could not read the permissions endpoint - the bicep deployment will surface it if the permission is missing"
        return
    }

    if ($hasWrite) {
        RecordPreflightCheck -Name "RBAC: role assignment rights" -Status OK -Detail "roleAssignments/write on $scopeLabel"
        return
    }

    RecordPreflightCheck -Name "RBAC: role assignment rights" -Status MISSING -Detail "The deploying account lacks Microsoft.Authorization/roleAssignments/write on $scopeLabel - azureresources.bicep creates two role assignments, and ARM rejects the whole deployment at submit without it" -Fix "Grant the account Owner or User Access Administrator on the subscription or the resource group."
}

# ---------------------------------------------------------------------------
# Resource provider registration
# A fresh subscription has most resource providers unregistered, and the deployment
# then fails with MissingSubscriptionRegistration - seen in the wild for
# Microsoft.Automation, with Microsoft.Logic queued up as the next failure across
# all nine logic apps. Registration is a SUBSCRIPTION-level action: Owner on the
# resource group gives nothing here, so the RBAC granted for the deployment itself
# does not cover it.
#
# Pre-flight (ValidateResourceProviders) checks the states. Unregistered providers
# are either queued for automatic registration - started right after the
# confirmation prompt, awaited just before the Azure deployments, so site creation
# usually absorbs the wait - or, when the account provably lacks subscription-scope
# rights, the run stops with the exact commands a subscription admin must run.
# ---------------------------------------------------------------------------
$script:providersToRegister = @()

function ValidateResourceProviders {
    $required = @()
    if (-not $SkipBicepDeploy) { $required += @('Microsoft.Automation', 'Microsoft.ManagedIdentity') }
    if (-not $SkipDeployARMTemplates) { $required += @('Microsoft.Logic', 'Microsoft.Web') }
    if ($required.Count -eq 0) { return }

    $unregistered = @()
    foreach ($namespace in $required) {
        $state = az provider show --namespace $namespace --subscription $parameters.subscriptionId.Value --query registrationState --output tsv 2>$null
        if ($state -ne 'Registered') {
            $unregistered += $namespace
        }
    }
    if ($unregistered.Count -eq 0) {
        RecordPreflightCheck -Name "Resource providers" -Status OK -Detail "$($required -join ', ') all registered"
        return
    }

    # Registering needs <namespace>/register/action at subscription scope. When the
    # permissions endpoint CONFIRMS the account lacks it, report MISSING with the
    # admin commands. An unreadable endpoint does not block: the registration
    # attempt after confirmation will give the verdict.
    $canRegister = TestAzureAction -Scope "/subscriptions/$($parameters.subscriptionId.Value)" -Action "$($unregistered[0])/register/action"
    if ($canRegister -eq $false) {
        $adminCommands = @($unregistered | ForEach-Object { "az provider register --namespace $_" }) -join ' ; '
        RecordPreflightCheck -Name "Resource providers" -Status MISSING -Detail "Not registered: $($unregistered -join ', ') - and the deploying account cannot register them (registration is a subscription-level action; a role on the resource group does not help)" -Fix "Have a subscription Contributor/Owner run: $adminCommands (takes a few minutes; verify with 'az provider show --namespace <ns> --query registrationState')."
        return
    }

    $script:providersToRegister = $unregistered
    RecordPreflightCheck -Name "Resource providers" -Status OK -Detail "$($unregistered -join ', ') not registered, but the account can register them - done automatically after confirmation"
}

# Node.js is only needed for the SPFx build, which is the LAST deploy step - a
# missing Node would otherwise surface after everything else succeeded.
function CheckNodeJs {
    if ($SkipSPFxDeploy) {
        RecordPreflightCheck -Name "Node.js (SPFx build)" -Status SKIPPED -Detail "-SkipSPFxDeploy"
        return
    }
    $nodeVersionRaw = if (Get-Command node -ErrorAction SilentlyContinue) { (node --version) 2>$null } else { $null }
    if ([string]::IsNullOrWhiteSpace($nodeVersionRaw)) {
        RecordPreflightCheck -Name "Node.js (SPFx build)" -Status MISSING -Detail "node was not found on PATH" -Fix "Install Node.js 22.14+ (https://nodejs.org), or run with -SkipSPFxDeploy."
        return
    }
    try {
        $nodeVersion = [version]($nodeVersionRaw.TrimStart('v'))
        if ($nodeVersion -lt [version]'22.14.0') {
            RecordPreflightCheck -Name "Node.js (SPFx build)" -Status MISSING -Detail "$nodeVersionRaw installed, 22.14+ required" -Fix "Update Node.js (https://nodejs.org), or run with -SkipSPFxDeploy."
            return
        }
        RecordPreflightCheck -Name "Node.js (SPFx build)" -Status OK -Detail "$nodeVersionRaw"
    }
    catch {
        RecordPreflightCheck -Name "Node.js (SPFx build)" -Status UNKNOWN -Detail "Could not parse 'node --version' output '$nodeVersionRaw'"
    }
}

# The tenant app catalog must exist before Add-PnPApp can publish the SPFx packages.
# Read on the -admin connection the main flow has already established.
function CheckAppCatalog {
    if ($SkipSPFxDeploy) {
        RecordPreflightCheck -Name "Tenant app catalog" -Status SKIPPED -Detail "-SkipSPFxDeploy"
        return
    }
    try {
        $appCatalogUrl = Get-PnPTenantAppCatalogUrl -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($appCatalogUrl)) {
            RecordPreflightCheck -Name "Tenant app catalog" -Status MISSING -Detail "No tenant app catalog exists - publishing the SPFx packages will fail" -Fix "Create it in the SharePoint admin center (https://learn.microsoft.com/sharepoint/use-app-catalog), or run with -SkipSPFxDeploy."
        }
        else {
            RecordPreflightCheck -Name "Tenant app catalog" -Status OK -Detail "$appCatalogUrl"
        }
    }
    catch {
        RecordPreflightCheck -Name "Tenant app catalog" -Status UNKNOWN -Detail "Could not read the app catalog url ($(($_.Exception.Message -split "`r?`n")[0]))"
    }
}

# App role assignment needs Global Administrator (or Privileged Role Administrator +
# Cloud Application Administrator). Detection is best-effort via the account's ACTIVE
# directory roles - a PIM-eligible role that is not activated will not show, so a
# negative result is a WARNING pointing at -SkipAppRoles, never a MISSING.
function CheckAppRoleRights {
    if ($SkipAppRoles) {
        RecordPreflightCheck -Name "App role assignment rights" -Status SKIPPED -Detail "-SkipAppRoles: a handover command for a Global Administrator is printed instead"
        return
    }
    try {
        # memberOf, NOT transitiveMemberOf. The transitive variant pages over the account's
        # entire membership set and applies the directoryRole cast per page, so an account
        # with many group memberships gets page after page of "value": [] with an
        # @odata.nextLink - reading only the first page then "proves" the account holds no
        # roles at all. Seen on a permanent Global Administrator: 20 pages, all empty.
        # memberOf returns every role in one response.
        $rolesJson = az rest --method get --url "https://graph.microsoft.com/v1.0/me/memberOf/microsoft.graph.directoryRole?`$select=displayName,roleTemplateId" 2>$null
        if (-not $rolesJson) { throw "the directory role lookup returned nothing" }
        $roles = @(($rolesJson | ConvertFrom-Json).value)
        $roleTemplates = @($roles.roleTemplateId)

        $isGlobalAdmin = $roleTemplates -contains '62e90394-69f5-4237-9190-012177145e10'
        $isPraPlusCaa = ($roleTemplates -contains 'e8611ab8-c189-46e8-94e1-60213ab1f814') -and ($roleTemplates -contains '158c047a-c907-4556-b7ef-446551a6b5f7')
        if ($isGlobalAdmin -or $isPraPlusCaa) {
            RecordPreflightCheck -Name "App role assignment rights" -Status OK -Detail $(if ($isGlobalAdmin) { "Global Administrator" } else { "Privileged Role Administrator + Cloud Application Administrator" })
        }
        else {
            # Name what the account DOES hold - "no GA detected" alone leaves you guessing
            # whether the role is missing, not activated, or held via a group (which this
            # non-transitive lookup does not see).
            $held = if ($roles.Count -gt 0) { "holds: $(($roles.displayName | Sort-Object) -join ', ')" } else { "no directory roles returned for the account" }
            RecordPreflightCheck -Name "App role assignment rights" -Status WARNING -Detail "Could not confirm Global Administrator (or Privileged Role Administrator + Cloud Application Administrator) - $held. PIM-eligible roles do not count until activated, and a role held through a group is not visible here" -Fix "Activate the role, or run with -SkipAppRoles and hand the printed command to a Global Administrator. If you know the account has it, just run - the app role step fails loudly if it does not."
        }
    }
    catch {
        RecordPreflightCheck -Name "App role assignment rights" -Status UNKNOWN -Detail "Could not read the account's directory roles - the app role step will surface it"
    }
}

# Kicks off the registrations queued by ValidateResourceProviders. Deliberately
# WITHOUT --wait: registration takes minutes, and the site creation that follows
# takes minutes anyway - WaitForResourceProviders picks up the result right before
# the first deployment that needs it.
function RegisterResourceProviders {
    foreach ($namespace in $script:providersToRegister) {
        Write-Host "Registering resource provider $namespace (in the background)..." -ForegroundColor Yellow
        az provider register --namespace $namespace --subscription $parameters.subscriptionId.Value --output none
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to start registration of resource provider $namespace - see the error above. Have a subscription Contributor/Owner run 'az provider register --namespace $namespace' and re-run this script."
        }
    }
}

function WaitForResourceProviders {
    if ($script:providersToRegister.Count -eq 0) { return }
    Write-Host "Waiting for resource provider registration to complete..." -ForegroundColor Yellow
    $deadline = [DateTime]::UtcNow.AddMinutes(10)
    $pending = @($script:providersToRegister)
    while ($true) {
        $stillPending = @()
        foreach ($namespace in $pending) {
            $state = az provider show --namespace $namespace --subscription $parameters.subscriptionId.Value --query registrationState --output tsv 2>$null
            if ($state -eq 'Registered') {
                Write-Host "  $namespace : Registered" -ForegroundColor Green
            }
            else {
                $stillPending += $namespace
            }
        }
        $pending = $stillPending
        if ($pending.Count -eq 0) { break }
        if ([DateTime]::UtcNow -gt $deadline) {
            throw "Resource provider(s) still not registered after 10 minutes: $($pending -join ', '). Check the state with 'az provider show --namespace <ns> --query registrationState' and re-run the script when it says Registered."
        }
        Start-Sleep -Seconds 15
    }
    $script:providersToRegister = @()
}

# Fails the deployment when the site alias would collide with the service account.
#
# The alias becomes the Microsoft 365 group's mailNickname, so it shares a namespace
# with every user and group in the tenant. A service account named after the solution
# (bestillingsportalen@<domain>) therefore owns the alias the solution wants. SharePoint
# does not report this as an error: it creates the group as '<alias>1' instead, the URL
# no longer matches what this script computed, and the run dies further down with
# "Object reference not set to an instance of an object" from the first cmdlet that
# addresses the expected URL. Better to stop here, before anything is created.
#
# Runs after ValidateServiceAccount so the account's mailNickname is known.
function ValidateSiteAlias {
    $upn = $parameters.serviceAccountUPN.Value
    $collidesWith = $null

    # A collision only matters when a NEW site is to be created - the alias becomes
    # the new group's mailNickname at creation time and never again. When the site
    # already exists on the computed URL, skip the check entirely. This is not just
    # an optimization: after a site URL rename (SharePoint admin center changes the
    # URL but NOT the group's mailNickname), requestsSiteAlias must be set to the new
    # URL segment, which may well be the service account's name - the very collision
    # this check exists for on fresh installs.
    $siteState = GetSiteExistenceState $requestsSiteUrl
    if ($siteState -eq 'Exists') {
        RecordPreflightCheck -Name "Site alias '$requestsSiteAlias'" -Status OK -Detail "The site already exists at $requestsSiteUrl"
        return
    }
    if ($siteState -eq 'Unknown' -and $null -ne $script:spoAdminAccessError) {
        # Same root cause as the admin-access check, which is already blocking - one red
        # line for it, not two.
        RecordPreflightCheck -Name "Site alias '$requestsSiteAlias'" -Status SKIPPED -Detail "Cannot tell whether the site exists while the tenant admin API is unavailable - see 'SharePoint admin access'"
        return
    }
    if ($siteState -eq 'Unknown') {
        # Blocking on purpose. An unanswered lookup is not "no site here": on an existing
        # installation it sends the run into the creation path, which ends at a prompt
        # offering to delete the customer's group and its site.
        # The connected identity goes in the detail, not a pointer to the PRE-FLIGHT
        # SUMMARY: that is printed by ConfirmDeployment, which both -Preflight and a
        # failing checklist exit before reaching. Naming the account is the whole point
        # of the message, so it has to be here.
        RecordPreflightCheck -Name "SharePoint tenant site lookup" -Status MISSING -Detail "Could not read $requestsSiteUrl to see whether it already exists (signed in to SharePoint as: $(GetPnPSignedInUser)): $script:siteLookupError" -Fix "That account must be a SharePoint Administrator in THIS tenant. Signing in again does not help: PnP.PowerShell caches the account on disk and -Interactive then completes silently as that account. Clear it, then re-run: Remove-Item `"`$env:LOCALAPPDATA\.m365pnppowershell\pnp.msal.cache`" -Force"
        return
    }

    # Computed from the UPN, not from ValidateServiceAccount's lookup - the alias
    # check must work even when the service account check failed.
    if ([string]::IsNullOrWhiteSpace($script:serviceAccountUpnLocalPart)) {
        $script:serviceAccountUpnLocalPart = ($upn -split '@')[0]
    }

    if ($requestsSiteAlias -ieq $script:serviceAccountUpnLocalPart) {
        $collidesWith = "the service account's UPN ($upn)"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($script:serviceAccountMailNickname) -and
        $requestsSiteAlias -ieq $script:serviceAccountMailNickname) {
        $collidesWith = "the service account's mail nickname ($($script:serviceAccountMailNickname))"
    }

    # Any user holding the alias causes the same rename, not just the service account -
    # a shared mailbox or another account named after the solution does it too. The
    # existing checks in CreateRequestsSharePointSite only look for GROUPS on the alias,
    # which is what missed this in practice. Best-effort: skip quietly if the lookup
    # fails, the specific check above still stands.
    if ($null -eq $collidesWith) {
        try {
            $aliasUserJson = az rest --method get --url "https://graph.microsoft.com/v1.0/users?`$filter=mailNickname eq '$requestsSiteAlias'&`$select=userPrincipalName,displayName" 2>$null
            $aliasUser = if ($aliasUserJson) { @(($aliasUserJson | ConvertFrom-Json).value) | Select-Object -First 1 } else { $null }
            if ($null -ne $aliasUser) {
                $collidesWith = "an existing user: '$($aliasUser.displayName)' ($($aliasUser.userPrincipalName))"
            }
        }
        catch {}
    }

    if ($null -eq $collidesWith) {
        RecordPreflightCheck -Name "Site alias '$requestsSiteAlias'" -Status OK -Detail "No user or service account holds it"
        return
    }

    # A collision still blocks the run: SharePoint would silently create the group as
    # '<alias>1' and every computed URL would be wrong. But the site no longer has to
    # end up on /sites/bestillingsportalen - the web parts and the Teams app locate it
    # via the tenant registry (storage entity bp_ProvisionUrls), which deploy.ps1
    # maintains automatically - so the fix is simply to pick a free alias.
    $suggestion = "BP"
    if ($requestsSiteAlias -ieq $suggestion) { $suggestion = "$requestsSiteAlias-site" }
    RecordPreflightCheck -Name "Site alias '$requestsSiteAlias'" -Status MISSING -Detail "Collides with $collidesWith - SharePoint would silently create the group as '$($requestsSiteAlias)1' and every computed URL would be wrong" -Fix "Set requestsSiteAlias in $parametersFileName to a free alias (e.g. '$suggestion') and re-run. Any alias works: the web parts and the Teams app locate the site via the tenant registry (storage entity bp_ProvisionUrls), which deploy.ps1 maintains automatically. See Deployment-guide.md."
}

# Reads the language (LCID) of the tenant's root site collection for the pre-flight
# summary. Provisioning sites in a language other than the root site's has caused
# problems, so the language is stated up front instead of being discovered afterwards.
#
# Read from the root WEB (Web.Language), not from Get-PnPTenantSite: SiteProperties
# has an Lcid member but does not reliably populate it - a real tenant reported 0.
# The pre-flight runs on the -admin connection, so the root web is read over a
# SEPARATE connection object (-ReturnConnection) that leaves the default connection
# untouched; the token from the first sign-in is reused, so no extra browser prompt.
# Never throws - a failure to read a display value must not abort a deployment that
# has not changed anything yet.
# Reports the result of the tenant-admin probe taken right after the PnP sign-in. Every
# SharePoint step downstream assumes this works, so it is the first thing on the checklist
# and it blocks: with it broken, half the remaining checks report nonsense.
function CheckSpoAdminAccess {
    if ($null -eq $script:spoAdminAccessError) {
        RecordPreflightCheck -Name "SharePoint admin access" -Status OK -Detail "$script:pnpIdentity"
        return
    }
    RecordPreflightCheck -Name "SharePoint admin access" -Status MISSING -Detail "Signed in as $script:pnpIdentity, but the tenant admin API returned: $script:spoAdminAccessError" -Fix "That account must be a SharePoint Administrator in THIS tenant. Signing in again does not help: PnP.PowerShell caches the account on disk and -Interactive then completes silently as that account. Clear it, then re-run: Remove-Item `"`$env:LOCALAPPDATA\.m365pnppowershell\pnp.msal.cache`" -Force"
}

# Tenants that enforce "MFA for Azure" refuse management-plane WRITES from a session that
# authenticated with a password alone - reads work fine, so nothing shows until the first
# deployment. That lands at azureresources.bicep, after the whole SharePoint part has run:
# AADSTS50076 from the CLI, or RequestDisallowedByAzure from ARM. Re-running is safe (every
# step is idempotent), but it is a wasted half-run, so read the claim up front.
#
# WARNING and not MISSING on purpose: enforcement depends on the tenant's policy, and a
# password-only session was seen completing a full deployment earlier the same day. Blocking
# would stop runs that work.
function CheckAzureWriteMfa {
    try {
        $armToken = az account get-access-token --resource https://management.azure.com --query accessToken --output tsv 2>$null
        if ([string]::IsNullOrWhiteSpace($armToken)) { throw "no ARM token from the Azure CLI" }

        # Only the amr claim is read out of the token, and the token itself is never logged.
        $payload = ($armToken -split '\.')[1]
        switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
        $claims = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload.Replace('-', '+').Replace('_', '/'))) | ConvertFrom-Json
        $methods = @($claims.amr)

        if ($methods -contains 'mfa') {
            RecordPreflightCheck -Name "MFA on the Azure session" -Status OK -Detail "amr: $($methods -join ', ')"
            return
        }
        RecordPreflightCheck -Name "MFA on the Azure session" -Status WARNING -Detail "The Azure CLI session authenticated without MFA (amr: $($methods -join ', ')) - a tenant that enforces MFA for Azure will refuse the deployments" -Fix "If a deployment fails with AADSTS50076 or RequestDisallowedByAzure, the CLI prints an 'az login' command with a --claims-challenge argument: run 'az logout' and then THAT command, verbatim. The challenge carries the Conditional Access authentication context the tenant demands (acrs), and -Scope alone does not satisfy it - a plain re-login just hands back the same password-only token. Note that az logout clears the cached CLI sessions for every tenant on the machine."
    }
    catch {
        RecordPreflightCheck -Name "MFA on the Azure session" -Status UNKNOWN -Detail "Could not read the Azure CLI token to check for an MFA claim - a deployment failing with AADSTS50076 means it was missing"
    }
}

function GetPnPSignedInUser {
    try {
        # No Get-PnPCurrentUser in PnP.PowerShell 3.x - read Web.CurrentUser over CSOM.
        $pnpContext = Get-PnPContext
        $currentUser = $pnpContext.Web.CurrentUser
        $pnpContext.Load($currentUser)
        $pnpContext.ExecuteQuery()

        $identity = $currentUser.Email
        if ([string]::IsNullOrWhiteSpace($identity)) {
            # LoginName is claims-encoded (i:0#.f|membership|user@tenant.com) - the UPN is
            # the last segment.
            $identity = ("$($currentUser.LoginName)" -split '\|')[-1]
        }
        return $identity
    }
    catch {
        return "could not be read ($(($_.Exception.Message -split "`r?`n")[0]))"
    }
}

function GetRootSiteLanguage {
    try {
        $rootConnection = Connect-PnPOnline -Url $global:tenantUrl -ClientId $parameters.pnpAppId.Value -Interactive -ReturnConnection -ErrorAction Stop
        $rootWeb = Get-PnPWeb -Includes Language -Connection $rootConnection -ErrorAction Stop
        $lcid = [int]$rootWeb.Language
        if ($lcid -le 0) {
            return "not reported by $global:tenantUrl"
        }
        try {
            # Resolve the name from the LCID rather than keeping a lookup table. The
            # solution's own Locales list is not available yet - it lives on the site
            # this run is about to create.
            return "$lcid - $([System.Globalization.CultureInfo]::GetCultureInfo($lcid).DisplayName)"
        }
        catch {
            return "$lcid"
        }
    }
    catch {
        # First line only - a CSOM/throttling error can run for paragraphs and would
        # wreck the summary layout.
        $reason = ($_.Exception.Message -split "`r?`n")[0]
        return "could not be read ($reason)"
    }
}

# CAML for a single settings row by Title. Get-PnPListItem -Query takes a full View,
# not just the Where clause.
function SettingQuery {
    param([Parameter(Mandatory = $true)][string]$Title)

    return "<View><Query><Where><Eq><FieldRef Name='Title'/><Value Type='Text'>$Title</Value></Eq></Where></Query><RowLimit>1</RowLimit></View>"
}

# Reads the version a previous run stamped into the settings list, so the checklist and
# the pre-flight summary can show what this run upgrades FROM. Same approach as
# GetRootSiteLanguage: a SEPARATE connection (-ReturnConnection) leaves the -admin
# connection the pre-flight runs on untouched, and the cached token means no extra
# browser prompt. Never throws - on a new installation the site does not exist yet,
# which is a normal outcome and returns $null.
function GetInstalledVersion {
    try {
        # Same existence check ValidateSiteAlias uses, on the -admin connection the
        # pre-flight already holds: on a new installation there is nothing to read, and
        # connecting to a site that does not exist is slow and noisy for no reason.
        if ($null -eq (Get-PnPTenantSite -Url $requestsSiteUrl -ErrorAction SilentlyContinue)) { return $null }

        $siteConnection = Connect-PnPOnline -Url $requestsSiteUrl -ClientId $parameters.pnpAppId.Value -Interactive -ReturnConnection -ErrorAction Stop
        $item = @(Get-PnPListItem -List $requestSettingsListName -Query (SettingQuery $installedVersionSettingName) -Connection $siteConnection -ErrorAction Stop)
        if ($item.Count -eq 0) { return $null }
        $value = "$($item[0].FieldValues['Value'])".Trim()
        if ([string]::IsNullOrEmpty($value)) { return $null }
        return $value
    }
    catch {
        return $null
    }
}

# A bad or missing VERSION file does not stop anything - it only means the installation
# gets stamped "unknown", which is worth seeing before the run rather than discovering
# months later in a support case. Doubles as the place the installed version is read,
# so -Preflight also reports what a full run would upgrade from.
function CheckVersionFile {
    $script:previousInstalledVersion = GetInstalledVersion
    $installed = if ($script:previousInstalledVersion) { "installed: $script:previousInstalledVersion" } else { "no version stamped in the environment yet" }

    if ($script:versionFileIssue) {
        RecordPreflightCheck -Name "Solution version" -Status WARNING -Detail "$script:versionFileIssue - the installation would be stamped 'unknown' ($installed)" -Fix "Restore VERSION in the repo root as a single MAJOR.MINOR.PATCH line (e.g. 2.0.0), or pull the repository again."
        return
    }
    RecordPreflightCheck -Name "Solution version" -Status OK -Detail "$deployVersion ($installed)"
}

# ---------------------------------------------------------------------------
# Pre-flight summary and confirmation
# Runs after all sign-ins so it reflects the ACTUAL connected identity,
# tenant and subscription - the last chance to abort before anything is
# created or changed in the environment. Skipped with -SkipConfirmation.
# ---------------------------------------------------------------------------
function ConfirmDeployment {
    if ($SkipConfirmation) {
        Write-Host "Skipping pre-flight confirmation (-SkipConfirmation)" -ForegroundColor Yellow
        return
    }

    $azContext = Get-AzContext

    Write-Host ""
    Write-Host "#################### PRE-FLIGHT SUMMARY ####################" -ForegroundColor Magenta
    Write-Host ""
    Write-Host ("  Version:              {0}{1}" -f $deployVersion, $(if ($script:previousInstalledVersion) { " (installed: $script:previousInstalledVersion)" })) -ForegroundColor Cyan
    Write-Host ("  Mode:                 {0}" -f $(if ($global:upgrade) { "UPGRADE of existing environment" } else { "FULL DEPLOYMENT" })) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Connected to:" -ForegroundColor Yellow
    Write-Host "    Parameter file:     $parametersFileName"
    Write-Host "    Entra ID tenant:    $($parameters.fullTenantName.Value) ($($parameters.tenantId.Value))"
    Write-Host "    Azure subscription: $($azContext.Subscription.Name) ($($azContext.Subscription.Id))"
    Write-Host "    Signed in as (Az):  $($azContext.Account.Id)"
    if (-not [string]::IsNullOrEmpty($deployUser)) {
        Write-Host "    Signed in as (CLI): $deployUser"
    }
    Write-Host "    SharePoint tenant:  $global:tenantUrl"
    # The PnP identity is the one that decides whether the site can be read and the
    # template applied, and it is picked in a browser prompt - which happily reuses a
    # cached account from another tenant. Worth seeing next to the Az/CLI identities.
    Write-Host "    Signed in as (PnP): $(GetPnPSignedInUser)"
    Write-Host "    Root site language: $(GetRootSiteLanguage)"
    Write-Host ("    Service account:    {0}{1}" -f $parameters.serviceAccountUPN.Value, $(if ($script:serviceAccountDisplayName) { " ($script:serviceAccountDisplayName) - verified" }))
    Write-Host ""
    Write-Host "  Will set up / update:" -ForegroundColor Yellow

    function WritePlanLine([string]$Label, [string]$Value, [bool]$Skipped = $false) {
        if ($Skipped) {
            Write-Host ("    {0,-20}(skipped)" -f "$($Label):") -ForegroundColor DarkGray
        }
        else {
            Write-Host ("    {0,-20}{1}" -f "$($Label):", $Value)
        }
    }

    WritePlanLine "Resource group" "$($parameters.resourceGroupName.Value) ($($parameters.region.Value))" ($SkipCreateResourceGroup -or $global:upgrade)
    WritePlanLine "SharePoint site" "$requestsSiteUrl (alias '$requestsSiteAlias'; prompts before overwriting an existing site)" $SkipSharepointSite
    WritePlanLine "Azure resources" "Automation account '$automationAccountName', managed identity '$uamiName' (azureresources.bicep)" $SkipBicepDeploy
    if ($SkipAppRoles) {
        WritePlanLine "App roles" "(skipped - a handover command for a Global Administrator is printed instead)" $true
    }
    else {
        WritePlanLine "App roles" "Graph/SharePoint roles on '$uamiName' + Automation system-assigned MI (only missing roles are added)"
    }
    WritePlanLine "Runbooks" "ConfigureSpace, AddGuestToSite, GetSiteTemplates (content published from Source/Runbooks/)"
    if ($global:upgrade) {
        WritePlanLine "Logic Apps" "ProcessProvisionRequest + ProcessGuestRequest (upgrade set)" $SkipDeployARMTemplates
    }
    else {
        WritePlanLine "API connections" "5 connections (4 require manual authorisation afterwards)" ($SkipDeployARMTemplates -or $SkipDeployAPIConnections)
        WritePlanLine "Logic Apps" "9 logic apps" $SkipDeployARMTemplates
    }
    WritePlanLine "SPFx packages" "Build + publish to the tenant app catalog" $SkipSPFxDeploy

    Write-Host ""
    Write-Host "############################################################" -ForegroundColor Magenta
    $confirm = Read-Host "Continue with this deployment? ( y / n )"
    if ($confirm -ne "y") {
        Write-Host "Deployment cancelled by user - nothing has been changed in the environment." -ForegroundColor Yellow
        exit 0
    }
    Write-Host "Confirmed - starting deployment..." -ForegroundColor Green
}

# -SkipAppRoles: assigning app roles is the only step that needs Global Administrator
# (or Privileged Role Administrator + Cloud Application Administrator). This function
# replaces the two assignment functions in that scenario: it resolves the identities'
# object ids and prints the exact AssignPermissionsToManagedIdentity.ps1 command a
# Global Administrator must run - the role sets are baked into that script, so the
# GA needs that ONE file and this ONE command, nothing else from the deployment.
function EmitAppRoleHandover {
    Write-Host "Skipping app role assignment (-SkipAppRoles) - building the handover command for a Global Administrator..." -ForegroundColor Yellow

    $autoPrincipalId = az resource show --resource-group $parameters.resourceGroupName.Value --name $automationAccountName --resource-type "Microsoft.Automation/automationAccounts" --query identity.principalId --output tsv 2>$null
    $uamiPrincipalId = az identity show --resource-group $parameters.resourceGroupName.Value --name $uamiName --query principalId --output tsv 2>$null

    $handoverArgs = @("-TenantId", $parameters.tenantId.Value)
    if (-not [string]::IsNullOrWhiteSpace($autoPrincipalId)) {
        $handoverArgs += @("-AutomationIdentityId", $autoPrincipalId.Trim())
    }
    else {
        Write-Host "WARN: Could not resolve the automation account's system-assigned identity - the handover command below lacks -AutomationIdentityId. Find the object id under the automation account's Identity blade and add it." -ForegroundColor Yellow
    }
    if (-not [string]::IsNullOrWhiteSpace($uamiPrincipalId)) {
        $handoverArgs += @("-UamiId", $uamiPrincipalId.Trim())
    }
    else {
        Write-Host "WARN: Could not resolve the user-assigned managed identity '$uamiName' - the handover command below lacks -UamiId. Find the object id on the identity resource and add it." -ForegroundColor Yellow
    }
    $handoverCommand = "./AssignPermissionsToManagedIdentity.ps1 " + ($handoverArgs -join ' ')

    Write-Host ""
    Write-Host "  App roles were NOT assigned. Send Source/Scripts/AssignPermissionsToManagedIdentity.ps1 to a Global Administrator" -ForegroundColor Cyan
    Write-Host "  (or Privileged Role Administrator + Cloud Application Administrator) and have them run:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    $handoverCommand" -ForegroundColor White
    Write-Host ""
    Write-Host "  Requires PowerShell 7+ and the Microsoft.Graph module (Install-Module Microsoft.Graph.Applications)." -ForegroundColor Cyan
    Write-Host "  The logic apps get 401/403 at runtime until this has been run. Safe to re-run - existing roles are skipped." -ForegroundColor Cyan
    Write-Host ""

    RecordDeployStatus -Component "App roles: $automationAccountName (system-assigned MI)" -Status 'SKIPPED' -Detail "Run as Global Administrator: $handoverCommand"
    RecordDeployStatus -Component "App roles: $uamiName (user-assigned MI)" -Status 'SKIPPED' -Detail "Covered by the same command - see the line above"
}

function AssignManagedIdentityPermissions {
    Write-Host "Assigning app roles to managed identity ($automationAccountName)..." -ForegroundColor Yellow

    # Resolve the system-assigned identity via the automation account RESOURCE, not by
    # display name - display-name lookup returns multiple service principals when
    # earlier (deleted) installs left orphans behind, which breaks every downstream
    # parameter binding ("Cannot convert value to type System.String").
    $autoPrincipalId = az resource show --resource-group $parameters.resourceGroupName.Value --name $automationAccountName --resource-type "Microsoft.Automation/automationAccounts" --query identity.principalId --output tsv 2>$null
    if ([string]::IsNullOrEmpty($autoPrincipalId)) {
        RecordDeployStatus -Component "App roles: $automationAccountName (system-assigned MI)" -Status 'FAILED' -Detail 'Could not resolve the automation account system-assigned identity'
        throw "Could not resolve the system-assigned managed identity for automation account '$automationAccountName' in resource group '$($parameters.resourceGroupName.Value)'. Ensure azureresources.bicep has been deployed."
    }

    $paAutoServicePrincipal = Get-AzADServicePrincipal -ObjectId $autoPrincipalId
    if ($null -eq $paAutoServicePrincipal) {
        RecordDeployStatus -Component "App roles: $automationAccountName (system-assigned MI)" -Status 'FAILED' -Detail "Service principal $autoPrincipalId not found"
        throw "The automation account's managed identity ($autoPrincipalId) was not found in Entra ID. If it was JUST created, replication may be lagging - wait a minute and re-run."
    }

    $spoResource = Get-AzADServicePrincipal -DisplayName "Office 365 SharePoint Online"
    $graphResource = Get-AzADServicePrincipal -DisplayName "Microsoft Graph"

    $existing = Get-AzADServicePrincipalAppRoleAssignment -ServicePrincipalId $paAutoServicePrincipal.Id

    # Idempotent — checked per AppRoleId (not just per resource), so re-runs add
    # only what's missing. Used by upgrade mode too so role grants stay in sync
    # as the runbooks evolve. AddGuestToSite needs Group.ReadWrite.All (mutate group
    # membership) AND User.Read.All (Add-PnPMicrosoft365GroupMember resolves the
    # guest by email via GET /users/{email} before posting members/$ref — without
    # User.Read.All this lookup returns 403 Insufficient privileges).
    $rolesToGrant = @(
        @{
            ResourceSp  = $spoResource
            RoleName    = 'Sites.FullControl.All'
            DisplayName = 'Have full control of all site collections'
        },
        @{
            ResourceSp  = $graphResource
            RoleName    = 'Group.ReadWrite.All'
            DisplayName = 'Read and write all groups'
        },
        @{
            ResourceSp  = $graphResource
            RoleName    = 'User.Read.All'
            DisplayName = "Read all users' full profiles"
        }
    )

    $failedRoles = @()
    foreach ($role in $rolesToGrant) {
        if ($null -eq $role.ResourceSp) {
            Write-Host "  WARN: Resource service principal for '$($role.RoleName)' was not found in the tenant. Skipping." -ForegroundColor Red
            $failedRoles += $role.RoleName
            continue
        }

        $appRole = $role.ResourceSp.AppRole | Where-Object { $_.Value -eq $role.RoleName -or $_.DisplayName -eq $role.DisplayName }
        if ($null -eq $appRole) {
            Write-Host "  WARN: Could not find app role '$($role.RoleName)' on $($role.ResourceSp.DisplayName)." -ForegroundColor Red
            $failedRoles += $role.RoleName
            continue
        }

        $alreadyAssigned = $existing | Where-Object { $_.AppRoleId -eq $appRole.Id }
        if ($null -ne $alreadyAssigned) {
            Write-Host "  $($role.RoleName) already assigned to $($role.ResourceSp.DisplayName). Skipping." -ForegroundColor Gray
            continue
        }

        Write-Host "  Granting $($role.RoleName) on $($role.ResourceSp.DisplayName)..." -ForegroundColor Yellow
        try {
            New-AzADServicePrincipalAppRoleAssignment -ServicePrincipalId $paAutoServicePrincipal.Id -AppRoleId $appRole.Id -ResourceId $role.ResourceSp.Id | Out-Null
            Write-Host "  $($role.RoleName) granted." -ForegroundColor Green
        }
        catch {
            Write-Host "  ERROR granting $($role.RoleName): $($_.Exception.Message)" -ForegroundColor Red
            $failedRoles += $role.RoleName
        }
    }

    if ($failedRoles.Count -gt 0) {
        RecordDeployStatus -Component "App roles: $automationAccountName (system-assigned MI)" -Status 'FAILED' -Detail "Missing: $($failedRoles -join ', '). Re-run the script or repair with AssignPermissionsToManagedIdentity.ps1."
    }
    else {
        RecordDeployStatus -Component "App roles: $automationAccountName (system-assigned MI)" -Status 'OK'
    }
    Write-Host "Finished assigning app roles to managed identity." -ForegroundColor Green
}

# Assigns Graph and SharePoint app roles to the user-assigned managed identity that the
# logic apps use for HTTP actions and the Key Vault/Azure Automation API connections.
# Replaces the application permissions previously carried by the Entra ID app (certificate).
function AssignUamiPermissions {
    Write-Host "Assigning app roles to user-assigned managed identity ($uamiName)..." -ForegroundColor Yellow

    if ([string]::IsNullOrEmpty($global:uamiPrincipalId)) {
        $global:uamiPrincipalId = az identity show --resource-group $parameters.resourceGroupName.Value --name $uamiName --query principalId --output tsv
    }
    if ([string]::IsNullOrEmpty($global:uamiPrincipalId)) {
        RecordDeployStatus -Component "App roles: $uamiName (user-assigned MI)" -Status 'FAILED' -Detail 'Managed identity not found'
        throw "Could not find user-assigned managed identity '$uamiName' in resource group '$($parameters.resourceGroupName.Value)'. Ensure azureresources.bicep has been deployed."
    }

    $spoResource = Get-AzADServicePrincipal -DisplayName "Office 365 SharePoint Online"
    $graphResource = Get-AzADServicePrincipal -DisplayName "Microsoft Graph"

    $existing = Get-AzADServicePrincipalAppRoleAssignment -ServicePrincipalId $global:uamiPrincipalId

    # Least-privilege set for the logic apps' Graph/SharePoint HTTP actions - each role is
    # tied to concrete runtime calls (see Data-access-security.md for the mapping).
    # Idempotent - checked per AppRoleId, so re-runs add only what's missing.
    #   SPO Sites.FullControl.All        - POST /_api/SPSiteManager/create (site creation; the
    #                                      target site doesn't exist yet, so Sites.Selected is
    #                                      not applicable) + ApplySiteDesign on the new site
    #   Directory.Read.All               - GET /groupLifecyclePolicies (documented least privilege)
    #   GroupSettings.ReadWrite.All      - POST /groups/{id}/settings (disable guest sharing per group)
    #   Group.ReadWrite.All              - create groups/teams, add/remove owners and members
    #   InformationProtectionPolicy.Read.All - sync sensitivity labels (SyncLabels)
    #   Sites.Read.All                   - CheckSiteExists reads of the tenant-admin aggregated site list
    #   TeamTemplates.Read.All          - sync Teams templates (GetTeamsTemplates)
    #   Community.ReadWrite.All          - create Viva Engage communities
    #   User.Invite.All                  - POST /invitations (guest invites)
    #   User.ReadWrite.All               - PATCH profile fields on invited guest users
    $rolesToGrant = @(
        @{ ResourceSp = $spoResource; RoleName = 'Sites.FullControl.All' },
        @{ ResourceSp = $graphResource; RoleName = 'Directory.Read.All' },
        @{ ResourceSp = $graphResource; RoleName = 'GroupSettings.ReadWrite.All' },
        @{ ResourceSp = $graphResource; RoleName = 'Group.ReadWrite.All' },
        @{ ResourceSp = $graphResource; RoleName = 'InformationProtectionPolicy.Read.All' },
        @{ ResourceSp = $graphResource; RoleName = 'Sites.Read.All' },
        @{ ResourceSp = $graphResource; RoleName = 'TeamTemplates.Read.All' },
        @{ ResourceSp = $graphResource; RoleName = 'Community.ReadWrite.All' },
        @{ ResourceSp = $graphResource; RoleName = 'User.Invite.All' },
        @{ ResourceSp = $graphResource; RoleName = 'User.ReadWrite.All' }
    )

    $failedRoles = @()
    foreach ($role in $rolesToGrant) {
        if ($null -eq $role.ResourceSp) {
            Write-Host "  WARN: Resource service principal for '$($role.RoleName)' was not found in the tenant. Skipping." -ForegroundColor Red
            $failedRoles += $role.RoleName
            continue
        }

        $appRole = $role.ResourceSp.AppRole | Where-Object { $_.Value -eq $role.RoleName -and $_.AllowedMemberType -contains 'Application' }
        if ($null -eq $appRole) {
            Write-Host "  WARN: Could not find app role '$($role.RoleName)' on $($role.ResourceSp.DisplayName)." -ForegroundColor Red
            $failedRoles += $role.RoleName
            continue
        }

        $alreadyAssigned = $existing | Where-Object { $_.AppRoleId -eq $appRole.Id }
        if ($null -ne $alreadyAssigned) {
            Write-Host "  $($role.RoleName) already assigned on $($role.ResourceSp.DisplayName). Skipping." -ForegroundColor Gray
            continue
        }

        Write-Host "  Granting $($role.RoleName) on $($role.ResourceSp.DisplayName)..." -ForegroundColor Yellow
        try {
            New-AzADServicePrincipalAppRoleAssignment -ServicePrincipalId $global:uamiPrincipalId -AppRoleId $appRole.Id -ResourceId $role.ResourceSp.Id | Out-Null
            Write-Host "  $($role.RoleName) granted." -ForegroundColor Green
        }
        catch {
            Write-Host "  ERROR granting $($role.RoleName): $($_.Exception.Message)" -ForegroundColor Red
            $failedRoles += $role.RoleName
        }
    }

    if ($failedRoles.Count -gt 0) {
        RecordDeployStatus -Component "App roles: $uamiName (user-assigned MI)" -Status 'FAILED' -Detail "Missing: $($failedRoles -join ', '). The logic apps will get 401/403 at runtime until these are assigned. Re-run the script or repair with AssignPermissionsToManagedIdentity.ps1."
    }
    else {
        RecordDeployStatus -Component "App roles: $uamiName (user-assigned MI)" -Status 'OK'
    }
    Write-Host "Finished assigning app roles to user-assigned managed identity." -ForegroundColor Green
}


# Deploy ARM templates
# The azureautomation connection is the only one that changed authentication model in
# 2.0: from the Entra ID app's credentials to the user-assigned managed identity. On a
# FRESH install it is created for managed identity and reports 'Ready'. On an upgrade from
# before 2.0 it already exists, holding the app registration's certificate credentials, and
# ARM only switches parameterValueType to 'Alternative' - the old stored credential stays,
# fails to refresh (AADSTS700027 once the Key Vault certificate has rotated), and leaves
# the connection in 'Error'. The designer then calls it "Invalid connection", and the
# runtime sends the runbook call with NO Authorization header: ConfigureSpace never starts
# and the request dies with "Authentication failed. The 'Authorization' header is missing."
#
# Recreating is the only way out, and it costs nothing - a managed identity connection
# holds no credentials and needs no consent, unlike the four delegated ones.
#
# Runs AFTER the connections template, never before: a connection carrying a dead
# credential sits at whatever status it last recorded - typically 'Connected' from the
# original install, because nothing has tried to refresh it since. It is the template's own
# update that triggers the refresh, and only then does the status turn 'Error'. Checking
# first therefore finds nothing to repair on the very run that breaks it, and the fix
# lands one deployment too late (seen exactly that way: an upgrade left the environment
# broken, and only a second run repaired it).
function RepairAutomationConnection {
    # Mirrors the resource name in apiconnections.json.
    $connectionName = "bestillingsportalen-automation"
    $connectionArgs = @('-g', $parameters.resourceGroupName.Value, '-n', $connectionName, '--resource-type', 'Microsoft.Web/connections')

    $status = az resource show @connectionArgs --query "properties.statuses[0].status" --output tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($status)) {
        RecordDeployStatus -Component "API connection: $connectionName" -Status 'FAILED' -Detail "The connection does not exist after the deployment - the runbook calls have nothing to go through"
        return
    }
    if ($status -in @('Ready', 'Connected')) {
        return
    }

    Write-Host "The $connectionName connection is '$status' - recreating it (a managed identity connection holds no credentials, so nothing is lost)..." -ForegroundColor Yellow
    az resource delete @connectionArgs --output none
    if ($LASTEXITCODE -ne 0) {
        RecordDeployStatus -Component "API connection: $connectionName" -Status 'FAILED' -Detail "Status '$status' and it could not be deleted for recreation - the runbook calls will fail with a missing Authorization header until it is recreated"
        Write-Host "WARN: could not delete $connectionName. Delete it manually in the portal and re-run - provisioning fails at the ConfigureSpace step until then." -ForegroundColor Yellow
        return
    }

    # Recreate it through the same template, so the definition stays in one place.
    az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/apiconnections.json' --parameters "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "location=$($global:location)" --output none

    $newStatus = az resource show @connectionArgs --query "properties.statuses[0].status" --output tsv 2>$null
    if ($newStatus -in @('Ready', 'Connected')) {
        RecordDeployStatus -Component "API connection: $connectionName" -Status 'OK' -Detail "Was '$status', recreated for managed identity - now '$newStatus'"
    }
    else {
        RecordDeployStatus -Component "API connection: $connectionName" -Status 'FAILED' -Detail "Recreated, but the status is '$newStatus' - the runbook calls will fail with a missing Authorization header"
    }
}

function DeployARMTemplates {
    try {
        # Deploy ARM templates
        if (-not $SkipDeployAPIConnections) {
            Write-Host "Deploying api connections..." -ForegroundColor Yellow

            az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/apiconnections.json' --parameters "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "location=$($global:location)" --output none
            RecordAzResult "API connections" -DeploymentName "apiconnections"

            # After the deployment: the update above is what surfaces a dead credential on
            # an upgraded environment. See the comment on the function.
            RepairAutomationConnection

            Write-Host "Finished deploying api connections..." -ForegroundColor Green
        }
        else {
            Write-Host "Skipping deployment of api connections..." -ForegroundColor Yellow
            RecordDeployStatus -Component "API connections" -Status 'SKIPPED'
        }
       
        Write-Host "Deploying logic apps..." -ForegroundColor Yellow

        Write-Host "ProcessGuests" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/processguests.json' --parameters  "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "location=$($global:location)" "uamiName=$uamiName" --output none
        RecordAzResult "Logic App: ProcessGuests" -DeploymentName "processguests"

        Write-Host "CheckSiteExists" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/checksiteexists.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "spoTenantName=$($parameters.spoTenantName.Value)" "location=$($global:location)" "uamiName=$uamiName" --output none
        RecordAzResult "Logic App: CheckSiteExists" -DeploymentName "checksiteexists"
        
        Write-Host "ProcessProvisionRequest" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/processprovisionrequest.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "automationAccountName=$automationAccountName" "requestsSiteUrl=$requestsSiteUrl" "requestsListId=$global:requestsListId" "location=$($global:location)" "requestsSettingsListId=$global:requestsSettingsListId" "tenantName=$($parameters.spoTenantName.Value)" "serviceAccountUPN=$($parameters.serviceAccountUPN.value)" "uamiName=$uamiName" "spoRootSiteUrl=$global:tenantUrl" --output none
        RecordAzResult "Logic App: ProcessProvisionRequest" -DeploymentName "processprovisionrequest"

        Write-Host "ProcessGuestRequest" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/processguestrequest.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "location=$($global:location)" "requestsSiteUrl=$requestsSiteUrl" "guestRequestsListId=$global:guestRequestsListId" "automationAccountName=$automationAccountName" "tenantName=$($parameters.spoTenantName.Value)" "uamiName=$uamiName" "guestEntraGroup=$($parameters.guestEntraGroup.Value)" --output none
        RecordAzResult "Logic App: ProcessGuestRequest" -DeploymentName "processguestrequest"

        Write-Host "SyncGroupSettings" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/syncgroupsettings.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "requestsSiteUrl=$requestsSiteUrl" "location=$($global:location)" "requestsSettingsListId=$global:requestsSettingsListId" "uamiName=$uamiName" --output none
        RecordAzResult "Logic App: SyncGroupSettings" -DeploymentName "syncgroupsettings"

        Write-Host "GetSiteTemplates" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/getsitetemplates.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "requestsSiteUrl=$requestsSiteUrl" "location=$($global:location)" "siteTemplatesListId=$global:siteTemplatesListId" "automationAccountName=$automationAccountName" "uamiName=$uamiName" --output none
        RecordAzResult "Logic App: GetSiteTemplates" -DeploymentName "getsitetemplates"
        
        Write-Host "GetHubSites" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/gethubsites.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "tenantName=$($parameters.spoTenantName.Value)" "requestsSiteUrl=$requestsSiteUrl" "location=$($global:location)" "hubSitesListId=$global:hubSitesListId" "uamiName=$uamiName" "spoRootSiteUrl=$global:tenantUrl" --output none
        RecordAzResult "Logic App: GetHubSites" -DeploymentName "gethubsites"
        
        Write-Host "SyncLabels" -ForegroundColor Yellow
        
        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/synclabels.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "location=$($global:location)" "requestsSiteUrl=$requestsSiteUrl" "ipLabelsListId=$global:ipLabelsListId" "uamiName=$uamiName" --output none
        RecordAzResult "Logic App: SyncLabels" -DeploymentName "synclabels"

        Write-Host "GetTeamsTemplates" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/getteamstemplates.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "requestsSiteUrl=$requestsSiteUrl" "location=$($global:location)" "teamsTemplatesListId=$global:teamsTemplatesListId" "tenantId=$($parameters.tenantId.Value)" "uamiName=$uamiName" --output none
        RecordAzResult "Logic App: GetTeamsTemplates" -DeploymentName "getteamstemplates"
        
        Write-Host "Finished deploying logic apps" -ForegroundColor Green
    }
    catch {
        throw('Failed to deploy the Azure resources {0}', $_.Exception.Message)
    }
}

# Confirms each runbook is actually linked to the PowerShell 7.4 runtime environment.
#
# Worth checking explicitly for two reasons:
#   1. The runbooks require PnP.PowerShell 3.x, which needs PowerShell 7.4. A runbook
#      left on the classic 5.1 runtime fails with "Connect-PnPOnline is not recognized".
#   2. The portal's default Runbooks blade ("old experience") displays every runbook
#      linked to a PowerShell 7.2+ runtime environment as "PowerShell 5.1" - a
#      documented display limitation, not a misconfiguration. Reporting the real value
#      here saves an afternoon of chasing a phantom problem.
#      https://learn.microsoft.com/en-us/azure/automation/runtime-environment-overview#limitations
function VerifyRunbookRuntimeEnvironment {
    Write-Host "Verifying runbook runtime environments..." -ForegroundColor Yellow

    $runbookApiBase = "https://management.azure.com/subscriptions/$($parameters.subscriptionId.Value)/resourceGroups/$($parameters.resourceGroupName.Value)/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runbooks"

    function Get-RunbookRuntime([string] $Name) {
        $value = az rest --method get --url "$runbookApiBase/$Name`?api-version=2024-10-23" --query "properties.runtimeEnvironment" --output tsv 2>$null
        if ([string]::IsNullOrWhiteSpace($value) -or $value -eq 'null') { return '(classic runtime)' }
        return $value
    }

    # The three repo-owned runbooks: deploy recreates these, so a mismatch is fixable.
    $wrong = @()
    foreach ($runbookName in @('ConfigureSpace', 'GetSiteTemplates', 'AddGuestToSite')) {
        $actual = Get-RunbookRuntime $runbookName
        if ($actual -eq $runtimeEnvironmentName) {
            Write-Host "  $runbookName : $actual" -ForegroundColor Green
        }
        else {
            Write-Host "  $runbookName : '$actual', expected '$runtimeEnvironmentName'" -ForegroundColor Red
            $wrong += "$runbookName ('$actual')"
        }
    }

    if ($wrong.Count -gt 0) {
        RecordDeployStatus -Component "Runbook runtime environment" -Status 'FAILED' -Detail "Not on '$runtimeEnvironmentName': $($wrong -join ', '). PnP.PowerShell 3.x needs PowerShell 7.4, so these runbooks will fail with 'Connect-PnPOnline is not recognized'. Re-link them under Automation account > Runtime environments, or delete the runbook and re-run deploy."
    }
    else {
        # The 'shows as PowerShell 5.1 in the portal' caveat is deliberately NOT
        # repeated here - it is documented in the deployment guide, and on an OK line
        # it read as a problem when there is none.
        RecordDeployStatus -Component "Runbook runtime environment" -Status 'OK' -Detail "On '$runtimeEnvironmentName' (PowerShell 7.4)"
    }

    # CustomerSpecific is customer-owned and deliberately never overwritten, so deploy
    # cannot fix it. Environments upgraded from before 2.0.0 may still have it on the
    # classic runtime - report it, but do not fail the deployment over it.
    $customerRuntime = Get-RunbookRuntime 'CustomerSpecific'
    if ($customerRuntime -eq $runtimeEnvironmentName) {
        Write-Host "  CustomerSpecific : $customerRuntime" -ForegroundColor Green
    }
    else {
        Write-Host "  CustomerSpecific : '$customerRuntime', expected '$runtimeEnvironmentName'" -ForegroundColor Yellow
        RecordDeployStatus -Component "Runbook: CustomerSpecific runtime" -Status 'WARNING' -Detail "On '$customerRuntime', not '$runtimeEnvironmentName'. Deploy never overwrites this runbook, so re-link it manually under Automation account > Runtime environments. Customer code using PnP 3.x cmdlets will otherwise fail."
    }

    Write-Host "  Note: the portal's default Runbooks blade shows 7.2+ runtime environments as 'PowerShell 5.1'. Use Automation account > Runtime environments to see the real value." -ForegroundColor Gray
}

# Deploy ProcessProvisionRequest + ProcessGuestRequest logic apps for upgrade scenarios
# See Upgrade.md for more details
function DeployLocalRunbooks {
    Write-Host "Deploying runbooks + PowerShell 7.4 runtime environment (runbooks.bicep)..." -ForegroundColor Yellow
    az deployment group create --subscription $parameters.subscriptionId.Value --resource-group $parameters.resourceGroupName.Value --template-file "../ARMTemplates/runbooks.bicep" --parameters "automationAccountName=$automationAccountName" "location=$($global:location)" --output none
    RecordAzResult "Runbooks + runtime environment (runbooks.bicep)" -DeploymentName "runbooks"

    # Upload the runbook content directly from the repo and publish. The bicep
    # template only creates empty runbook shells (publishContentLink would require a
    # publicly reachable URI, and this repo is private) - the content lives in
    # Source/Runbooks/ right next to this script, so push it via the management API.
    # This keeps the deployed content in sync with the repo on every run: portal-side
    # edits are overwritten on deploy/upgrade - customisations belong in the repo.
    $runbookApiBase = "https://management.azure.com/subscriptions/$($parameters.subscriptionId.Value)/resourceGroups/$($parameters.resourceGroupName.Value)/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runbooks"
    foreach ($runbookName in @('ConfigureSpace', 'GetSiteTemplates', 'AddGuestToSite')) {
        $runbookScript = Join-Path $packageRootPath "Runbooks/$runbookName.ps1"
        if (-not (Test-Path $runbookScript)) {
            RecordDeployStatus -Component "Runbook content: $runbookName" -Status 'FAILED' -Detail "Source file not found: $runbookScript"
            Write-Host "Runbook source $runbookScript not found - skipping content upload for $runbookName." -ForegroundColor Red
            continue
        }

        Write-Host "Publishing runbook content from repo: $runbookName..." -ForegroundColor Yellow
        $runbookScriptPath = (Resolve-Path $runbookScript).Path
        az rest --method put --url "$runbookApiBase/$runbookName/draft/content?api-version=2024-10-23" --headers "Content-Type=text/powershell" --body "@$runbookScriptPath" --output none
        if ($LASTEXITCODE -eq 0) {
            az rest --method post --url "$runbookApiBase/$runbookName/publish?api-version=2024-10-23" --output none
        }
        RecordAzResult "Runbook content: $runbookName"
    }

    # CustomerSpecific runbook: a customer extension point that ProcessProvisionRequest
    # invokes right after ConfigureSpace, with the same parameters. Created ONCE with
    # a default no-op content - and NEVER touched again by deploy/upgrade: the content
    # is owned by the customer/consultant (edit in the portal or a customer repo).
    az rest --method get --url "$runbookApiBase/CustomerSpecific?api-version=2024-10-23" --output none 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Creating CustomerSpecific runbook (customer extension point - deploys will never overwrite it)..." -ForegroundColor Yellow

        $shellBodyPath = Join-Path ([System.IO.Path]::GetTempPath()) "bp-customerspecific-shell.json"
        @{ location = $global:location; properties = @{ runbookType = 'PowerShell'; runtimeEnvironment = $runtimeEnvironmentName; logVerbose = $true; logProgress = $true; draft = @{} } } | ConvertTo-Json -Depth 4 | Set-Content $shellBodyPath

        az rest --method put --url "$runbookApiBase/CustomerSpecific?api-version=2024-10-23" --headers "Content-Type=application/json" --body "@$shellBodyPath" --output none
        if ($LASTEXITCODE -eq 0) {
            $customerScriptPath = (Resolve-Path (Join-Path $packageRootPath "Runbooks/CustomerSpecific.ps1")).Path
            az rest --method put --url "$runbookApiBase/CustomerSpecific/draft/content?api-version=2024-10-23" --headers "Content-Type=text/powershell" --body "@$customerScriptPath" --output none
        }
        if ($LASTEXITCODE -eq 0) {
            az rest --method post --url "$runbookApiBase/CustomerSpecific/publish?api-version=2024-10-23" --output none
        }
        RecordAzResult "Runbook: CustomerSpecific (created with default content)"
        Remove-Item $shellBodyPath -ErrorAction SilentlyContinue
    }
    else {
        Write-Host "CustomerSpecific runbook already exists - leaving it untouched (customer-owned content)." -ForegroundColor Gray
        RecordDeployStatus -Component "Runbook: CustomerSpecific" -Status 'OK' -Detail 'Existing customer-owned content preserved'
    }

    # After CustomerSpecific exists, so a fresh deploy does not report it as missing.
    VerifyRunbookRuntimeEnvironment

    Write-Host "Finished deploying runbooks (content published from Source/Runbooks/; CustomerSpecific is customer-owned)" -ForegroundColor Green
}

function DeployUpgradeLogicApp {
    try {
        Write-Host "### UPGRADE MODE - DEPLOYING UPGRADE LOGIC APPS ###" -ForegroundColor Yellow
        Write-Host "For upgrade documentation, see Upgrade.md" -ForegroundColor Cyan

        if ([string]::IsNullOrEmpty($global:requestsListId)) {
            throw "Provisioning Requests list ID not found. Did the PnP template apply succeed?"
        }
        if ([string]::IsNullOrEmpty($global:guestRequestsListId)) {
            throw "Guest Requests list ID not found. Did the PnP template apply succeed?"
        }

        Write-Host "ProcessProvisionRequest" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/processprovisionrequest.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "automationAccountName=$automationAccountName" "requestsSiteUrl=$requestsSiteUrl" "requestsListId=$global:requestsListId" "location=$($global:location)" "requestsSettingsListId=$global:requestsSettingsListId" "tenantName=$($parameters.spoTenantName.Value)" "serviceAccountUPN=$($parameters.serviceAccountUPN.value)" "uamiName=$uamiName" "spoRootSiteUrl=$global:tenantUrl" --output none
        RecordAzResult "Logic App: ProcessProvisionRequest" -DeploymentName "processprovisionrequest"

        Write-Host "ProcessGuestRequest" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/processguestrequest.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "location=$($global:location)" "requestsSiteUrl=$requestsSiteUrl" "guestRequestsListId=$global:guestRequestsListId" "automationAccountName=$automationAccountName" "tenantName=$($parameters.spoTenantName.Value)" "uamiName=$uamiName" "guestEntraGroup=$($parameters.guestEntraGroup.Value)" --output none
        RecordAzResult "Logic App: ProcessGuestRequest" -DeploymentName "processguestrequest"

        Write-Host "Finished deploying upgrade logic apps" -ForegroundColor Green
    }
    catch {
        throw('Failed to deploy logic apps in upgrade mode: {0}', $_.Exception.Message)
    }
}

# Connects PnP PowerShell to the given URL with interactive browser sign-in
# (delegated, as the account running the script). The deployment is attended by
# design - the script prompts throughout - so certificate/app-only auth is not
# supported. Only the FIRST connection in a run shows a browser prompt; the rest
# reuse the token.
#
# Note that PnP.PowerShell persists its MSAL token cache to disk regardless of
# -PersistLogin: %LOCALAPPDATA%\.m365pnppowershell\pnp.msal.cache. A warm cache makes
# -Interactive complete SILENTLY as whichever account is in it, so signing in "as the
# right account" is not something the script can ask for. Deleting that file is what
# actually forces a fresh account choice - Connect-PnPOnline -ForceAuthentication did
# not, when tested. The pre-flight site lookup surfaces the command when it matters.
function ConnectPnP {
    param([Parameter(Mandatory = $true)][string]$Url)

    Connect-PnPOnline -Url $Url -ClientId $parameters.pnpAppId.Value -Interactive
}

# Packages the solution's Teams app (teams/manifest.json + icons) and publishes it to the
# tenant's Teams app catalog via Graph, replacing the unreliable "Sync to Teams" button in
# the SharePoint app catalog. The app is matched on externalId (= the component id in the
# manifest), so an app previously synced from the app catalog is updated, not duplicated.
# Publishing requires the delegated Graph permission AppCatalog.ReadWrite.All on the PnP
# app (see Deployment-guide.md) - without it the zip is still produced and the manual
# upload path via the Teams admin center is printed.
function PublishTeamsApp {
    param([Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$Solution)

    $teamsFolder = Join-Path $Solution.FullName "teams"
    $manifestPath = Join-Path $teamsFolder "manifest.json"
    if (-not (Test-Path $manifestPath)) { return }

    $componentName = "Teams app: $($Solution.Name)"
    $zipPath = Join-Path $Solution.FullName "sharepoint/solution/bestillingsportalen-teams-app.zip"
    try {
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

        # The Teams app version follows the solution version (first three parts)
        $solutionVersion = (Get-Content (Join-Path $Solution.FullName "config/package-solution.json") -Raw | ConvertFrom-Json).solution.version
        $appVersion = ($solutionVersion -split '\.')[0..2] -join '.'

        # Stage icons + version-stamped manifest, and zip them (flat, no folder inside)
        $staging = Join-Path ([System.IO.Path]::GetTempPath()) "bp-teams-app-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $staging | Out-Null
        try {
            Get-ChildItem $teamsFolder -File | Where-Object Name -ne "manifest.json" | Copy-Item -Destination $staging
            $manifest.version = $appVersion
            $manifest | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $staging "manifest.json") -Encoding utf8
            Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $zipPath -Force
        }
        finally {
            Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Host "Packaged Teams app $appVersion -> $zipPath" -ForegroundColor Yellow

        $headers = @{ Authorization = "Bearer $(Get-PnPAccessToken)" }
        $filter = [uri]::EscapeDataString("externalId eq '$($manifest.id)'")
        $existing = (Invoke-RestMethod -Method Get -Headers $headers -Uri "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps?`$filter=$filter&`$expand=appDefinitions").value | Select-Object -First 1

        if ($existing -and ($existing.appDefinitions.version -contains $appVersion)) {
            Write-Host "Teams app '$($manifest.name.short)' $appVersion is already published" -ForegroundColor Green
            RecordDeployStatus -Component $componentName -Status 'OK'
            return
        }

        if ($existing) {
            Invoke-RestMethod -Method Post -Headers $headers -ContentType "application/zip" -InFile $zipPath -Uri "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps/$($existing.id)/appDefinitions" | Out-Null
            Write-Host "Updated Teams app '$($manifest.name.short)' to $appVersion in the Teams app catalog" -ForegroundColor Green
        }
        else {
            Invoke-RestMethod -Method Post -Headers $headers -ContentType "application/zip" -InFile $zipPath -Uri "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps" | Out-Null
            Write-Host "Published Teams app '$($manifest.name.short)' $appVersion to the Teams app catalog" -ForegroundColor Green
        }
        RecordDeployStatus -Component $componentName -Status 'OK'
    }
    catch {
        $reason = ($_.Exception.Message -split "`r?`n")[0]
        Write-Host "Teams app publish FAILED: $reason" -ForegroundColor Red
        Write-Host "Upload the package manually instead: Teams admin center -> Teams apps -> Manage apps -> Actions: Upload new app -> $zipPath" -ForegroundColor Yellow
        Write-Host "(Automatic publish requires the delegated Graph permission AppCatalog.ReadWrite.All on the PnP app - see Deployment-guide.md.)" -ForegroundColor Yellow
        # Surfaced again at the very end of the run - see WriteTeamsAppManualUploadNotice
        $global:teamsAppManualUploadZip = $zipPath
        RecordDeployStatus -Component $componentName -Status 'WARNING' -Detail "Publish failed ($reason). Upload $zipPath manually via the Teams admin center (Manage apps -> Upload new app)."
    }
}

# Repeats the manual Teams app upload instructions at the end of the run, where they
# won't be scrolled away by the output of later deployment steps. Most tenants won't
# grant the PnP app AppCatalog.ReadWrite.All, so this is the expected path.
function WriteTeamsAppManualUploadNotice {
    if (-not $global:teamsAppManualUploadZip) { return }
    Write-Host ""
    Write-Host "MANUAL STEP - Teams app was NOT published automatically (the PnP app most likely lacks the" -ForegroundColor Yellow
    Write-Host "delegated Graph permission AppCatalog.ReadWrite.All). Upload it in the Teams admin center:" -ForegroundColor Yellow
    Write-Host "  1. Teams admin center -> Teams apps -> Manage apps -> Actions: Upload new app" -ForegroundColor Yellow
    Write-Host "  2. Select: $global:teamsAppManualUploadZip" -ForegroundColor Yellow
    Write-Host "  If a 'Bestillingsportalen' app already exists, open it and use 'Upload file' to update it instead." -ForegroundColor Yellow
    Write-Host "  See 'Teams-appen' in Deployment-guide.md." -ForegroundColor Yellow
    Write-Host ""
}

# Build all SPFx solutions under Source/SharePointFramework/ and upload them to the tenant app catalog.
# Each subfolder with config/package-solution.json is treated as a solution to deploy.
function DeploySPFxPackages {
    try {
        Write-Host "### DEPLOYING SPFX SOLUTIONS ###" -ForegroundColor Yellow

        $spfxRoot = Join-Path $packageRootPath "SharePointFramework"
        if (-not (Test-Path $spfxRoot)) {
            Write-Host "No SharePointFramework folder at $spfxRoot - skipping SPFx deployment" -ForegroundColor Yellow
            return
        }

        if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
            throw "npm not installed. Install Node.js (https://nodejs.org) or use -SkipSPFxDeploy to skip SPFx build."
        }

        $spfxSolutions = Get-ChildItem -Path $spfxRoot -Directory | Where-Object {
            Test-Path (Join-Path $_.FullName "config/package-solution.json")
        }
        if ($spfxSolutions.Count -eq 0) {
            Write-Host "No SPFx solutions found under $spfxRoot" -ForegroundColor Yellow
            return
        }

        # Need an admin connection to resolve the tenant app catalog URL
        $adminUrl = "https://$($parameters.spoTenantName.Value)-admin.sharepoint.com"
        ConnectPnP $adminUrl

        $appCatalogUrl = Get-PnPTenantAppCatalogUrl
        if ([string]::IsNullOrEmpty($appCatalogUrl)) {
            throw "Tenant app catalog not found. Create one in SharePoint admin center first."
        }
        Write-Host "Tenant app catalog: $appCatalogUrl" -ForegroundColor Yellow

        # Connect to the app catalog for Add-PnPApp
        ConnectPnP $appCatalogUrl

        foreach ($solution in $spfxSolutions) {
            Write-Host ""
            Write-Host "Building SPFx solution: $($solution.Name)" -ForegroundColor Yellow

            Push-Location $solution.FullName
            try {
                if (-not (Test-Path "node_modules")) {
                    Write-Host "Running npm install (first build may take several minutes)..." -ForegroundColor Yellow
                    npm install
                    if ($LASTEXITCODE -ne 0) { throw "npm install failed for $($solution.Name)" }
                }

                Write-Host "Running npm run build..." -ForegroundColor Yellow
                npm run build
                if ($LASTEXITCODE -ne 0) { throw "npm run build failed for $($solution.Name)" }

                $sppkgFolder = Join-Path $solution.FullName "sharepoint/solution"
                $sppkg = Get-ChildItem -Path $sppkgFolder -Filter "*.sppkg" -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $sppkg) {
                    throw "No .sppkg produced for $($solution.Name) in $sppkgFolder"
                }

                Write-Host "Uploading $($sppkg.Name) to app catalog..." -ForegroundColor Yellow
                $app = Add-PnPApp -Path $sppkg.FullName -Overwrite -Publish -SkipFeatureDeployment
                Write-Host "Uploaded and published tenant-wide: $($app.Title)" -ForegroundColor Green
                RecordDeployStatus -Component "SPFx: $($solution.Name)" -Status 'OK'

                # Publish the solution's Teams app (if it ships one) to the Teams app catalog
                PublishTeamsApp -Solution $solution
            }
            catch {
                # Record and continue - a failed SPFx build should not abort the rest of
                # the deployment (the packages can be re-deployed with -SkipSharepointSite
                # or by re-running the script).
                Write-Host "SPFx solution $($solution.Name) FAILED: $($_.Exception.Message)" -ForegroundColor Red
                RecordDeployStatus -Component "SPFx: $($solution.Name)" -Status 'FAILED' -Detail $_.Exception.Message
            }
            finally {
                Pop-Location
            }
        }

        Write-Host "### SPFX DEPLOYMENT COMPLETE ###" -ForegroundColor Green
    }
    catch {
        RecordDeployStatus -Component "SPFx packages" -Status 'FAILED' -Detail $_.Exception.Message
        Write-Host "SPFx deployment FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Continuing - the SPFx packages can be deployed later by re-running the script with the relevant skip flags." -ForegroundColor Yellow
    }
}

#Check that the provided location is a valid Azure location
function ValidateAzureLocation {

    try {
        $locations = Get-AzLocation
    
        $global:location = $parameters.region.Value.Replace(" ", "").ToLower()

        # Validate that the location exists
        if ($null -eq ($locations | Where-Object Location -eq $global:location)) {
            throw "Invalid Azure Location. Please provide a valid location. See this list - https://azure.microsoft.com/en-gb/global-infrastructure/services/?products=automation&regions=all"

        }
    
        # Validate that the region supports Automation and Logic Apps (https://azure.microsoft.com/en-gb/global-infrastructure/services/?products=automation&regions=all)
        If (($global:location -eq "southafricawest") -or ($global:location -eq "australiacentral2") -or ($global:location -eq "australiacentral") -or ($global:location -eq "southafricawest") -or ($global:location -eq "canadaeast") -or ($global:location -eq "chinaeast") -or ($global:location -eq "germanynorth") -or ($global:location -eq "southindia") `
                -or ($global:location -eq "francesouth") -or ($global:location -eq "westindia") -or ($global:location -eq "japaneast") -or ($global:location -eq "koreasouth") -or ($global:location -eq "switzerlandnorth") -or ($global:location -eq "switzerlandnwest") -or ($global:location -eq "uaecentral") -or ($global:location -eq "uaenorth") -or ($global:location -eq "norwaywest") -or ($global:location -eq "germanywestcentral")) {
     
            throw "Azure location does not support Automation and/or Logic Apps. See this list for regions which support Automation - https://azure.microsoft.com/en-gb/global-infrastructure/services/?products=automation&regions=all"
     
        }
    }
    catch {
        throw('Failed to validate Azure location {0}', $_.Exception.Message)
    }
}

# Sends an anonymous deployment pingback to the shared PP365 install/deploy telemetry function.
# Mirrors the Prosjektportalen installation pingback. Best-effort only — never fails the deployment.
# Full deploy vs upgrade is distinguishable from InstallCommand (the invocation line, e.g. "deploy.ps1 -Upgrade").
# Reads script-scoped $deployVersion / $deployStartTime / $deployInvocationLine / $requestsSiteUrl / $deployUser / $global:appId.
function SendDeployPingback {
    Write-Host "Sending deployment pingback..." -ForegroundColor Yellow

    $deployEndTime = (Get-Date -Format o)

    $deployCommand = if ($null -ne $deployInvocationLine -and $deployInvocationLine.Length -gt 2) {
        $deployInvocationLine.Substring(2)
    }
    else {
        $deployInvocationLine
    }

    $deployEntry = @{
        Title            = "Bestillingsportalen $deployVersion"
        InstallStartTime = $deployStartTime
        InstallEndTime   = $deployEndTime
        InstallVersion   = $deployVersion
        InstallCommand   = $deployCommand
        InstallChannel   = "Bestillingsportalen"  # Product indicator (distinguishes from PP365 in the shared telemetry store)
        InstallUrl       = $requestsSiteUrl
    }

    if (-not [string]::IsNullOrEmpty($deployUser)) {
        $deployEntry.InstallUser = $deployUser
    }

    try {
        Invoke-WebRequest "https://pp365-install-pingback.azurewebsites.net/api/AddEntry" -Body ($deployEntry | ConvertTo-Json) -Method 'POST' -ErrorAction SilentlyContinue >$null 2>&1
    }
    catch {}
}

# Create-or-update a single row in the settings list, keyed on Title, so re-running the
# deployment updates the value instead of piling up duplicate rows.
function SetSettingValue {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $existing = @(Get-PnPListItem -List $requestSettingsListName -Query (SettingQuery $Title) -ErrorAction Stop)
    if ($existing.Count -eq 0) {
        Add-PnPListItem -List $requestSettingsListName -Values @{ Title = $Title; Value = $Value; Description = $Description } -ErrorAction Stop | Out-Null
    }
    else {
        Set-PnPListItem -List $requestSettingsListName -Identity $existing[0].Id -Values @{ Value = $Value; Description = $Description } -ErrorAction Stop | Out-Null
    }
}

# Upserts this installation into the tenant-wide instance registry (storage entity
# bp_ProvisionUrls) that the Bestillingsportalen web part/Teams app and the guest web
# part read to locate the site. The value is either a plain URL or a JSON array of
# {title, url} objects; the first entry is the tenant default. Set-PnPStorageEntity
# only works against the tenant app catalog connection. Plain read-modify-write
# without locking - acceptable since deployments are rare and run manually. Entries
# are never REMOVED here; decommissioned instances are cleaned up manually with
# Set-PnPStorageEntity. Best effort: a failure is a WARNING with the manual command,
# never fatal.
function RegisterProvisionInstance {
    $componentName = "Instance registry (bp_ProvisionUrls)"
    try {
        Write-Host "Registering $requestsSiteUrl in tenant storage entity bp_ProvisionUrls..." -ForegroundColor Yellow
        $instanceTitle = if (IsValidParam($parameters.provisionInstanceTitle)) {
            $parameters.provisionInstanceTitle.Value
        }
        else {
            $parameters.requestsSiteName.Value
        }

        # The token is cached in-session, so these do not prompt again
        ConnectPnP "https://$($parameters.spoTenantName.Value)-admin.sharepoint.com"
        $appCatalogUrl = Get-PnPTenantAppCatalogUrl
        if ([string]::IsNullOrEmpty($appCatalogUrl)) {
            throw "Tenant app catalog not found - create one in the SharePoint admin center"
        }
        ConnectPnP $appCatalogUrl

        $existingRaw = (Get-PnPStorageEntity -Key "bp_ProvisionUrls" -ErrorAction SilentlyContinue).Value
        $instances = @()
        if (-not [string]::IsNullOrWhiteSpace($existingRaw)) {
            $trimmed = $existingRaw.Trim()
            if ($trimmed.StartsWith('[')) {
                try { $instances = @($trimmed | ConvertFrom-Json -ErrorAction Stop) } catch { $instances = @() }
            }
            else {
                # Migrate a plain-string entity to the array format
                $instances = @([pscustomobject]@{ title = 'Bestillingsportalen'; url = $trimmed })
            }
        }

        $normalize = { param($u) "$u".Trim().TrimEnd('/').ToLowerInvariant() }
        $match = $instances | Where-Object { (& $normalize $_.url) -eq (& $normalize $requestsSiteUrl) } | Select-Object -First 1
        if ($null -ne $match) {
            $match.title = $instanceTitle
            $match.url = $requestsSiteUrl
        }
        else {
            $instances += [pscustomobject]@{ title = $instanceTitle; url = $requestsSiteUrl }
        }

        # Re-project to keep the entity clean, and -AsArray (via the pipeline, which
        # enumerates) so a single entry still serializes as a JSON array - passing the
        # array as an argument would double-wrap it
        $json = $instances | Select-Object title, url | ConvertTo-Json -Compress -AsArray
        Set-PnPStorageEntity -Key "bp_ProvisionUrls" -Value $json -Description "Bestillingsportalen-instanser (JSON-array av {title, url}; foerste element er standard). Vedlikeholdes av deploy.ps1 - kan ogsaa redigeres manuelt." -ErrorAction Stop
        Write-Host "Registered instance '$instanceTitle' -> $requestsSiteUrl ($(@($instances).Count) instance(s) in the registry)" -ForegroundColor Green
        RecordDeployStatus -Component $componentName -Status 'OK' -Detail "$instanceTitle -> $requestsSiteUrl"
    }
    catch {
        $reason = ($_.Exception.Message -split "`r?`n")[0]
        Write-Host "[WARNING] Failed to register the instance in bp_ProvisionUrls: $reason" -ForegroundColor Yellow
        Write-Host "Set it manually against the tenant app catalog: Set-PnPStorageEntity -Key bp_ProvisionUrls -Value $requestsSiteUrl" -ForegroundColor Yellow
        RecordDeployStatus -Component $componentName -Status 'WARNING' -Detail "Registry not updated ($reason). Set it manually against the tenant app catalog: Set-PnPStorageEntity -Key bp_ProvisionUrls -Value $requestsSiteUrl"
    }
}

# Stamps the deployed version into the environment so whoever supports this installation
# later can read it off: two rows in the settings list (visible to admins in SharePoint)
# and two tags on the resource group (visible in the Azure portal). Called from BOTH the
# upgrade branch and the full deployment, right before the pingback.
#
# The rows are written HERE and deliberately not seeded by the PnP template: the
# <pnp:DataRows> block uses UpdateBehavior="Skip", so a template-seeded version would
# freeze at whatever the first install wrote and never move on -Upgrade.
#
# Nothing is stamped when a component FAILED - a half-finished run must not claim to be
# a complete release. A failure to stamp is a WARNING, never fatal: the stamp is a
# reading aid, not a functional dependency.
function StampInstalledVersion {
    if ((GetFailedDeployComponents).Count -gt 0) {
        RecordDeployStatus -Component "Version stamp" -Status 'WARNING' -Detail "Not stamped - other components failed, so the environment keeps its previous version instead of being marked as $deployVersion"
        return
    }

    $stampTime = (Get-Date -Format o)
    $problems = @()

    try {
        # DeploySPFxPackages leaves the default PnP connection on the -admin site and runs
        # immediately before this in both branches - reconnect to the requests site. The
        # token is cached in-session, so this does not prompt again.
        ConnectPnP $requestsSiteUrl
        SetSettingValue -Title $installedVersionSettingName -Value $deployVersion -Description "Versjonen av Bestillingsportalen som sist ble installert. Settes automatisk av deploy.ps1 - ikke rediger manuelt."
        SetSettingValue -Title $installedDateSettingName -Value $stampTime -Description "Tidspunktet for siste installasjon eller oppgradering. Settes automatisk av deploy.ps1 - ikke rediger manuelt."
    }
    catch {
        $problems += "settings list: $(($_.Exception.Message -split "`r?`n")[0])"
    }

    try {
        # Merge, NOT Set-AzResourceGroup -Tag: that cmdlet replaces the whole tag set and
        # would wipe the customer's own governance tags (cost centre, owner, environment).
        $rgName = $parameters.resourceGroupName.Value
        $rgId = az group show --name $rgName --subscription $parameters.subscriptionId.Value --query id --output tsv 2>$null
        if ([string]::IsNullOrEmpty($rgId)) {
            $problems += "resource group tags: could not resolve the id of '$rgName'"
        }
        else {
            az tag update --resource-id $rgId --operation Merge --tags "BestillingsportalenVersion=$deployVersion" "BestillingsportalenDeployed=$stampTime" --output none 2>$null
            if ($LASTEXITCODE -ne 0) {
                $problems += "resource group tags: az tag update exited with code $LASTEXITCODE"
            }
        }
    }
    catch {
        $problems += "resource group tags: $(($_.Exception.Message -split "`r?`n")[0])"
    }

    $versionDetail = if ($script:previousInstalledVersion -and $script:previousInstalledVersion -ne $deployVersion) {
        "$deployVersion (was $script:previousInstalledVersion)"
    }
    else {
        $deployVersion
    }

    if ($problems.Count -gt 0) {
        RecordDeployStatus -Component "Version stamp" -Status 'WARNING' -Detail "$versionDetail - partially stamped: $($problems -join ' | ')"
        return
    }
    RecordDeployStatus -Component "Version stamp" -Status 'OK' -Detail "$versionDetail - settings list + resource group tags"
}

$ErrorActionPreference = "stop"

# Print the (partial) deployment summary even when the script stops on a
# terminating error, so it is clear which components completed before the failure.
trap {
    WriteDeploymentReport
    break
}

Write-Host "###  DEPLOYMENT SCRIPT STARTED ###" -ForegroundColor Magenta

# Capture start metadata for the deployment pingback (sent at the end of the run)
$deployStartTime = (Get-Date -Format o)
$deployInvocationLine = $MyInvocation.Line
$deployUser = $null

if (-not $SkipVerifyModules) {
    # Verify required PS Modules
    Write-Host "Verifying installation of required PowerShell Modules..." -ForegroundColor Yellow
    VerifyModules
    Write-Host "Required modules are installed" -ForegroundColor Green
}

# PnP.PowerShell and Az ship different versions of the Microsoft.Extensions.*
# assemblies. If Az loads first, Connect-PnPOnline fails with a TypeLoadException
# ("Method 'get_Services' in type '...LoggingBuilder' ... does not have an
# implementation"). Importing PnP.PowerShell BEFORE the first Az cmdlet lets its
# assemblies load first - Az isolates its own dependencies in a custom assembly
# load context and tolerates this. If the error still occurs, start a FRESH
# PowerShell session (a session where Az has already been loaded cannot be
# repaired by import order).
# Already loaded is already correct - and it is the only thing that works when the module
# lives outside PSModulePath (a version side-loaded by path, which is how a new PnP release
# gets tested). Import-Module by NAME would fail there, on a session that has the module
# loaded and working.
# Nothing to report when it is already loaded - VerifyModules just printed the version and
# where it came from.
if ($null -eq (Get-Module -Name PnP.PowerShell)) {
    Write-Host "Loading PnP.PowerShell (must load before the Az module to avoid assembly conflicts)..." -ForegroundColor Yellow
    Import-Module PnP.PowerShell -ErrorAction Stop
}

# Load Parameters from json file (path validated at the top of the script)
$parametersListContent = Get-Content -LiteralPath $ParametersPath -ErrorAction Stop

# Validate all the parameters.
Write-Host "Validating all the parameters from $parametersFileName" -ForegroundColor Yellow
$parameters = $parametersListContent | ConvertFrom-Json
if (-not(ValidateParameters)) {
    Write-Host "Invalid parameters found. Please update the parameters in $parametersFileName with valid values and re-run the script." -ForegroundColor Red
    EXIT
}

Write-Host "Parameters are valid" -ForegroundColor Green

# Allow overriding the user-assigned managed identity name from the parameter file
if ($parameters.PSObject.Properties.Name -contains 'uamiName' -and (IsValidParam($parameters.uamiName))) {
    $uamiName = $parameters.uamiName.Value
}

Write-Ascii -InputObject "Bestillingsportalen" -ForegroundColor Green

# Set upgrade mode
$global:upgrade = $Upgrade
if ($global:upgrade) {
    Write-Host "" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "    RUNNING IN UPGRADE MODE" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "This will:" -ForegroundColor Cyan
    Write-Host "  - Apply PnP template WITHOUT populating list items" -ForegroundColor Cyan
    Write-Host "  - Deploy the ProcessProvisionRequest and ProcessGuestRequest Logic Apps" -ForegroundColor Cyan
    if (-not $SkipSPFxDeploy) {
        Write-Host "  - Build and publish SPFx solutions (Source/SharePointFramework/*) to the tenant app catalog" -ForegroundColor Cyan
    }
    else {
        Write-Host "  - Skip SPFx build/publish (-SkipSPFxDeploy was set)" -ForegroundColor Cyan
    }
    Write-Host "  - Skip uploading assets (images/icons)" -ForegroundColor Cyan
    Write-Host "  - Skip ALL other Azure resource deployments" -ForegroundColor Cyan
    Write-Host "" -ForegroundColor Yellow
    Write-Host "For complete upgrade documentation, see Upgrade.md" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Yellow
    
    # Automatically set skip flags for upgrade mode
    $SkipBicepDeploy = $true
    $SkipCreateResourceGroup = $true
    $SkipDeployAPIConnections = $true

    Write-Host "Automatically skipping: Bicep Deploy, Resource Group Creation, API Connections" -ForegroundColor DarkGray
    Write-Host "" -ForegroundColor Yellow
}

$global:tenantUrl = "https://$($parameters.spoTenantName.Value).sharepoint.com"

# The alias decides both the site URL and the Microsoft 365 group mail, so it is an
# explicit parameter rather than always derived from the title: a title like
# "Bestillingsportalen" derives the alias 'bestillingsportalen', which collides with a
# service account called bestillingsportalen@<domain> - and SharePoint resolves that
# collision by silently creating the group as 'bestillingsportalen1'.
#
# The default stays 'bestillingsportalen' as a recognizable convention, but any alias
# works: the web parts and the Teams app locate the site via the tenant registry
# (storage entity bp_ProvisionUrls) that RegisterProvisionInstance maintains. When the
# alias is taken, ValidateSiteAlias stops the run and says to pick a free one.
#
# Falls back to the old title-derived alias when the parameter is absent or blank, so
# existing parameters.json files keep pointing at the site they already installed.
if ($parameters.PSObject.Properties.Name -contains 'requestsSiteAlias' -and (IsValidParam($parameters.requestsSiteAlias))) {
    $requestsSiteAlias = ($parameters.requestsSiteAlias.Value -replace ' ', '').Trim().Trim('/')
}
else {
    $requestsSiteAlias = $parameters.requestsSiteName.Value -replace (' ', '')
}
$requestsSiteUrl = "https://$($parameters.spoTenantName.Value).sharepoint.com/$($parameters.managedPath.Value)/$requestsSiteAlias"

# Initialise connections - Azure Az/CLI. Both tools cache sessions across runs,
# so existing sessions matching the target tenant/subscription are offered for
# reuse instead of forcing a new MFA round trip on every run. -SkipConfirmation
# (which -Force implies) reuses a matching session without asking.

# --- Az PowerShell ---
Write-Host "Checking for an existing Az PowerShell session..." -ForegroundColor Yellow
$azConnect = $null
$existingAzContext = Get-AzContext -ErrorAction SilentlyContinue
if ($null -ne $existingAzContext -and $existingAzContext.Tenant.Id -eq $parameters.tenantId.Value) {
    Write-Host "Found existing Az PowerShell session: $($existingAzContext.Account.Id) in tenant $($existingAzContext.Tenant.Id)." -ForegroundColor Green
    $reuseAz = if ($SkipConfirmation) { 'y' } else { Read-Host "Reuse this session? ( y = reuse / n = sign in again )" }
    if ($reuseAz -eq 'y') {
        try {
            # Silent subscription switch - no re-authentication within the same tenant
            $azConnect = Set-AzContext -SubscriptionId $parameters.subscriptionId.Value -TenantId $parameters.tenantId.Value
        }
        catch {
            Write-Host "Could not switch the existing session to subscription $($parameters.subscriptionId.Value) - signing in again." -ForegroundColor Yellow
            $azConnect = $null
        }
    }
}
if ($null -eq $azConnect) {
    Write-Host "Launching Azure sign-in..." -ForegroundColor Yellow
    $azConnect = Connect-AzAccount -Subscription $parameters.subscriptionId.Value -Tenant $parameters.tenantId.Value
}

# Skip validation steps in upgrade mode
if (-not $global:upgrade) {
    if (-not $SkipBicepDeploy) {
    }
    ValidateAzureLocation
}

# --- Azure CLI ---
Write-Host "Checking for an existing Azure CLI session..." -ForegroundColor Yellow
$cliSignedIn = $false
$cachedSubsJson = az account list --output json 2>$null
$cachedSubs = if ($cachedSubsJson) { @($cachedSubsJson | ConvertFrom-Json) } else { @() }
$targetCliSub = $cachedSubs | Where-Object { $_.id -eq $parameters.subscriptionId.Value -and $_.tenantId -eq $parameters.tenantId.Value } | Select-Object -First 1
if ($null -ne $targetCliSub) {
    Write-Host "Found existing Azure CLI session: $($targetCliSub.user.name) with access to subscription '$($targetCliSub.name)'." -ForegroundColor Green
    $reuseCli = if ($SkipConfirmation) { 'y' } else { Read-Host "Reuse this session? ( y = reuse / n = sign in again )" }
    if ($reuseCli -eq 'y') {
        $cliSignedIn = $true
    }
}
if (-not $cliSignedIn) {
    Write-Host "Launching Azure CLI sign-in..." -ForegroundColor Yellow
    az login --tenant $parameters.tenantId.Value --only-show-errors | Out-Null
}
Write-Host "Connected to Azure" -ForegroundColor Green

# Change the subscription
az account set --subscription $parameters.subscriptionId.Value

# Capture the signed-in user (used for the deployment pingback and for granting the
# installing user site collection admin). Deliberately AFTER 'az account set': read
# before it, this returns whatever account the CLI happened to have selected - for anyone
# with cached sessions in several tenants, that is regularly a user from a different
# tenant than the one being deployed to. Best-effort; works in both deploy and upgrade mode.
try {
    $deployUser = az ad signed-in-user show --query userPrincipalName -o tsv 2>$null
}
catch {}

# Connect to PnP - the token is cached for the rest of this run, so only this
# first connection shows a browser prompt.
$adminSiteUrl = "https://$($parameters.spoTenantName.Value)-admin.sharepoint.com"
Write-Host "Launching PnP sign-in (a browser window will open - sign in with the account running this script)..." -ForegroundColor Yellow
ConnectPnP $adminSiteUrl

# Verify the connection rather than announce it. Connect-PnPOnline does not throw when it
# completes silently from PnP's on-disk token cache as an account with no rights in this
# tenant - the failure surfaces on the first tenant-admin read instead, far enough down
# that it reads as a permissions bug rather than a sign-in that picked the wrong account.
# Probing the tenant admin API here, with the identity named, turns that into one line.
$script:pnpIdentity = GetPnPSignedInUser
$script:spoAdminAccessError = $null
try {
    Get-PnPTenantSite -Url $global:tenantUrl -ErrorAction Stop | Out-Null
    Write-Host "Connected to SPO: $adminSiteUrl as $script:pnpIdentity" -ForegroundColor Green
}
catch {
    $script:spoAdminAccessError = ($_.Exception.Message -split "`r?`n")[0]
    Write-Host "Signed in to $adminSiteUrl as $script:pnpIdentity, but the tenant admin API did not answer - NOT usable yet, see the checklist below." -ForegroundColor Yellow
}

# All sign-ins are done and nothing has been changed yet - validate the templates and
# the service account, then show the pre-flight summary and ask for confirmation before
# the first mutating step.
# Every check RECORDS its result instead of stopping on first failure, so one run
# shows everything that is missing at once - permissions and prerequisites tend to
# need ordering from customer admins, and finding them one re-run at a time is slow.
# The checks themselves are quiet on success; the checklist below is the output.
Write-Host "Running pre-deployment checks (version, SharePoint admin access, MFA, templates, service account, site alias, RBAC, resource providers, app roles, app catalog, Node.js - takes ~30 seconds)..." -ForegroundColor Yellow
CheckVersionFile
CheckSpoAdminAccess
CheckAzureWriteMfa
ValidateArmTemplates
ValidateServiceAccount
ValidateSiteAlias
ValidateAzureRbac
ValidateResourceProviders
CheckAppRoleRights
CheckAppCatalog
CheckNodeJs

$missingCount = ShowPreflightChecklist

if ($Preflight) {
    Write-Host "Pre-flight only (-Preflight): nothing has been deployed or changed." -ForegroundColor Cyan
    if ($missingCount -gt 0) {
        Write-Host "Fix the $missingCount missing item(s) above and re-run - or run the full deployment when ready." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "All checks passed - ready to deploy." -ForegroundColor Green
    exit 0
}

if ($missingCount -gt 0) {
    Write-Host "$missingCount missing item(s) - fix them (see the checklist above) and re-run. Nothing has been changed in the environment." -ForegroundColor Red
    exit 1
}

ConfirmDeployment
RegisterResourceProviders

if (-not $SkipSharepointSite) {
    CreateRequestsSharePointSite
    # Connect to the new site
    ConnectPnP $requestsSiteUrl
    ConfigureSharePointSite

    # Skip uploading assets in upgrade mode - and when the operator answered NO to the
    # template prompt, which promises to "leave the site untouched". Uploading the
    # package's images and icons over the site's own is not untouched.
    if (-not $global:upgrade -and -not $global:skipApplyTemplate) {
        UploadAssets
    }
    RecordDeployStatus -Component "SharePoint site + PnP template" -Status 'OK'
}
else {
    # If we're skipping site creation/configuration, we need to get the list ids
    Write-Host "Skipping SharePoint site creation" -ForegroundColor Yellow
    RecordDeployStatus -Component "SharePoint site + PnP template" -Status 'SKIPPED'
    ConnectPnP $requestsSiteUrl
    $context = Get-PnPContext
    
    $siteRequestsList = Get-PnPList $requestsListName
    $context.Load($siteRequestsList)
    $context.ExecuteQuery()
    
    $global:requestsListId = $siteRequestsList.Id
    
    $siteRequestsSettingsList = Get-PnPList $requestSettingsListName
    $context.Load($siteRequestsSettingsList)
    $context.ExecuteQuery()
    
    # Get request settings list id
    $global:requestsSettingsListId = $siteRequestsSettingsList.Id
    
    # Get site templates List id
    $siteTemplatesList = Get-PnPList $siteTemplatesListName
    $context.Load($siteTemplatesList)
    $context.ExecuteQuery()
    
    $global:siteTemplatesListId = $siteTemplatesList.Id
    
    # Get hub sites List id
    $hubSitesList = Get-PnPList $hubSitesListName
    $context.Load($hubSitesList)
    $context.ExecuteQuery()
    
    $global:hubSitesListId = $hubSitesList.Id
    
    $teamsTemplatesList = Get-PnPList $teamsTemplatesListName
    $context.Load($teamsTemplatesList)
    $context.ExecuteQuery()
    
    $global:teamsTemplatesListId = $teamsTemplatesList.Id
    
    $ipLabelsList = Get-PnPList $ipLabelsListName
    $context.Load($ipLabelsList)
    $context.ExecuteQuery()
    $global:ipLabelsListId = $ipLabelsList.Id

    $guestRequestsList = Get-PnPList $guestRequestsListName
    $context.Load($guestRequestsList)
    $context.ExecuteQuery()
    $global:guestRequestsListId = $guestRequestsList.Id
}

# Skip Azure resource deployment in upgrade mode - only deploy Logic App
if ($global:upgrade) {
    Write-Host "### UPGRADE MODE - SKIPPING AZURE RESOURCE DEPLOYMENT ###" -ForegroundColor Yellow
    Write-Host "Only deploying ProcessProvisionRequest Logic App..." -ForegroundColor Yellow
    
    # Get the location from parameters for the logic app deployment
    $global:location = $parameters.region.Value.Replace(" ", "").ToLower()

    # Ensure new runbooks (e.g. AddGuestToSite in 2.0.0) exist BEFORE the Logic Apps
    # that invoke them are deployed.
    DeployLocalRunbooks

    # Idempotent — grants Sites.FullControl.All + Group.ReadWrite.All to the
    # automation account's system-assigned managed identity if not already
    # present. Needed by AddGuestToSite for Add-PnPMicrosoft365GroupMember/Owner.
    # Pre-2.0.0 deploys may have skipped this in upgrade mode.
    AssignManagedIdentityPermissions

    # The logic apps reference the user-assigned managed identity, which is created by
    # azureresources.bicep (skipped in upgrade mode). Installations deployed before the
    # managed identity migration must run a full deploy first - fail early with a clear
    # message instead of a cryptic ARM error. See Upgrade.md.
    $uamiExists = az identity show --resource-group $parameters.resourceGroupName.Value --name $uamiName --query principalId --output tsv 2>$null
    if ([string]::IsNullOrEmpty($uamiExists)) {
        throw "User-assigned managed identity '$uamiName' was not found in resource group '$($parameters.resourceGroupName.Value)'. Run a full deployment (without -Upgrade) once to migrate to managed identity before using upgrade mode. See Upgrade.md."
    }
    # Idempotent - keeps the UAMI app roles in sync as the logic apps evolve.
    AssignUamiPermissions

    DeployUpgradeLogicApp

    $spfxDeployed = $false
    if (-not $SkipSPFxDeploy) {
        DeploySPFxPackages
        $spfxDeployed = $true
    }
    else {
        Write-Host "Skipping SPFx deployment" -ForegroundColor Yellow
        RecordDeployStatus -Component "SPFx packages" -Status 'SKIPPED'
    }

    RegisterProvisionInstance

    StampInstalledVersion

    SendDeployPingback

    WriteDeploymentReport

    WriteTeamsAppManualUploadNotice

    if ((GetFailedDeployComponents).Count -gt 0) {
        Write-Host "### UPGRADE COMPLETED WITH ERRORS - SEE SUMMARY ABOVE ###" -ForegroundColor Red
        exit 1
    }

    Write-Host "### UPGRADE COMPLETED SUCCESSFULLY ###" -ForegroundColor Green
    if ($spfxDeployed) {
        Write-Host "ProcessProvisionRequest + ProcessGuestRequest Logic Apps and SPFx packages have been updated." -ForegroundColor Green
    }
    else {
        Write-Host "ProcessProvisionRequest + ProcessGuestRequest Logic Apps have been updated (SPFx deployment was skipped)." -ForegroundColor Green
    }

    exit 0
}

Write-Host "### AZURE RESOURCES DEPLOYMENT ###`nStarting Azure resources deployment..." -ForegroundColor Yellow

if (-not $SkipCreateResourceGroup) {
    # Create resource group
    # Handle spaces in resource group name
    $parameters.resourceGroupName.Value = $parameters.resourceGroupName.Value.Replace(" ", "")
    # Only create it when it is actually missing. New-AzResourceGroup on an existing group
    # asks "Provided resource group already exists. Are you sure you want to update it?" -
    # an interactive confirmation that -Force does not suppress, so an unattended run would
    # sit there waiting. Re-running against an existing environment is the normal case, and
    # it has nothing to create.
    $existingResourceGroup = Get-AzResourceGroup -Name $parameters.resourceGroupName.Value -ErrorAction SilentlyContinue
    if ($null -ne $existingResourceGroup) {
        Write-Host "Resource group $($parameters.resourceGroupName.Value) already exists in $($existingResourceGroup.Location) - leaving it as it is." -ForegroundColor Green
        RecordDeployStatus -Component "Resource group" -Status 'OK' -Detail "Already existed ($($existingResourceGroup.Location))"
    }
    else {
        Write-Host "Creating resource group $($parameters.resourceGroupName.Value)..." -ForegroundColor Yellow
        New-AzResourceGroup -Name $parameters.resourceGroupName.Value -Location $global:location | Out-Null
        Write-Host "Created resource group" -ForegroundColor Green
        RecordDeployStatus -Component "Resource group" -Status 'OK'
    }
}
else {
    Write-Host "Skipping resource group creation" -ForegroundColor Yellow
    RecordDeployStatus -Component "Resource group" -Status 'SKIPPED'
}

Write-Host "Deploying Azure resources" -ForegroundColor Yellow

# Registrations kicked off after the confirmation prompt have had the whole site
# provisioning to complete in - this blocks only if they are genuinely not done.
WaitForResourceProviders

if (-not $SkipBicepDeploy) {
    Write-Host "Deploying automation account and managed identity..." -ForegroundColor Yellow
    az deployment group create --subscription $parameters.subscriptionId.Value --resource-group $parameters.resourceGroupName.Value --template-file "../ARMTemplates/azureresources.bicep" --parameters "tenantId=$($parameters.tenantId.Value)" "logoUrl=$($parameters.siteLogoPath.Value)" "uamiName=$uamiName" --output none
    RecordAzResult "Azure resources (bicep: Automation, UAMI)" -DeploymentName "azureresources"
    if ($LASTEXITCODE -ne 0) {
        # Everything after this point (permissions, runbooks, logic apps) depends on
        # these resources - no point continuing.
        throw "azureresources.bicep deployment failed - see the error output above. Fix the cause and re-run the script."
    }
    if ($SkipAppRoles) {
        EmitAppRoleHandover
    }
    else {
        AssignManagedIdentityPermissions
        AssignUamiPermissions
    }
    DeployLocalRunbooks
    Write-Host "Finished deploying automation account and managed identity..." -ForegroundColor Green
}
else {
    Write-Host "Skipping azureresources.bicep deployment" -ForegroundColor Yellow
    RecordDeployStatus -Component "Azure resources (bicep: Automation, UAMI)" -Status 'SKIPPED'
    # The logic apps and API connections still need the app roles on the user-assigned
    # managed identity - keep them in sync even when the bicep deployment is skipped.
    if ($SkipAppRoles) {
        EmitAppRoleHandover
    }
    else {
        AssignUamiPermissions
    }
}

if (-not $SkipDeployARMTemplates) {
    # Upgrade mode never reaches this point (it exits after the upgrade block above)
    DeployARMTemplates
}
else {
    Write-Host "Skipping ARM template deployment" -ForegroundColor Yellow
    RecordDeployStatus -Component "Logic Apps + API connections" -Status 'SKIPPED'
}

Write-Host "Azure resources deployed`n### AZURE RESOURCES DEPLOYMENT COMPLETE ###" -ForegroundColor Green

if (-not $SkipSPFxDeploy) {
    DeploySPFxPackages
}
else {
    Write-Host "Skipping SPFx deployment" -ForegroundColor Yellow
    RecordDeployStatus -Component "SPFx packages" -Status 'SKIPPED'
}

RegisterProvisionInstance

StampInstalledVersion

SendDeployPingback

WriteDeploymentReport

Write-Host ""
# The manual steps are deliberately NOT enumerated here - a second copy of the
# guide's step list drifts out of sync with it. The guide is the single source.
Write-Host "The scripted part is done. Next: authorise the API connections as the service account" -ForegroundColor Cyan
Write-Host "('Autorisere API-tilkoblinger' in Deployment-guide.md - guided flow: ./Authorize-ApiConnections.ps1)," -ForegroundColor Cyan
Write-Host "then follow Configuration-guide.md for approval setup, flow import, sharing and a verification order." -ForegroundColor Cyan
Write-Host ""

WriteTeamsAppManualUploadNotice

if ((GetFailedDeployComponents).Count -gt 0) {
    Write-Host "### DEPLOYMENT COMPLETED WITH ERRORS - SEE SUMMARY ABOVE ###" -ForegroundColor Red
    exit 1
}

Write-Host "### DEPLOYMENT COMPLETED SUCCESSFULLY ###" -ForegroundColor Green
