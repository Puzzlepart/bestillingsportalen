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

    Parameters should be filled out in the parameters.json file before executing the script.

.EXAMPLE
    deploy.ps1
#>

<# Valid Azure locations that support Azure Automation & Logic Apps at the time of writing - https://azure.microsoft.com/en-gb/global-infrastructure/services/?products=logic-apps,automation&regions=all #>

param
(
    [Parameter(Mandatory = $false)]
    [switch]$SkipVerifyModules,
    [switch]$SkipSharepointSite,
    [switch]$SkipBicepDeploy,
    [switch]$SkipCreateResourceGroup,
    [switch]$SkipDeployARMTemplates,
    [switch]$SkipDeployAPIConnections,
    [switch]$SkipSPFxDeploy,
    [switch]$SkipConfirmation, # Skip the pre-flight summary/confirmation prompt (for unattended runs)
    [switch]$Upgrade  # See Upgrade.md for details on using upgrade mode
)

Add-Type -AssemblyName System.Web

# Ensure running on PowerShell 7.4+ (required by PnP.PowerShell 3.x)
if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version]'7.4') {
    Write-Host "This script requires PowerShell 7.4 or newer (current: $($PSVersionTable.PSVersion)). Install the latest PowerShell from https://aka.ms/powershell and re-run in a new session." -ForegroundColor Red
    exit 1
}

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
$settingsPath = "Settings\SharePoint List items.xlsx"

# Required PS modules (value = minimum version; $null = any version).
# PnP.PowerShell 3.2+ is required for the interactive/persisted login used by ConnectPnP.
$preReqModules = [ordered]@{
    'PnP.PowerShell' = [version]'3.2.0'
    'Az'             = $null
    'ImportExcel'    = $null
    'WriteAscii'     = $null
}

#  Worksheets
$provRequestSettingsWorksheetName = "Provisioning Request Settings"
$provTypesWorksheetName = "Provisioning Types"
$teamsTemplatesWorksheetName = "Teams Templates"
$timeZonesWorksheetName = "Time Zones"
$localesWorksheetName = "Locales"

#  lists
$requestsListName = "Provisioning Requests"
$requestSettingsListName = "Provisioning Request Settings"
$siteAssetsListURL = "SiteAssets"
$provTypesListName = "Provisioning Types"
$siteTemplatesListName = "Site Templates"
$hubSitesListName = "Hub Sites"
$teamsTemplatesListName = "Teams Templates"
$timeZonesListName = "Time Zones"
$localesListName = "Locales"
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
$uamiName = "bestillingsportalen-uami" # Overridden by the uamiName parameter in parameters.json if present

# Solution version reported via the deployment pingback. Bump on release (keep in sync with CHANGELOG.md).
$deployVersion = "1.11.0"

# Global variables
$global:context = $null
$global:requestsListId = $null
$global:requestsSettingsListId = $null
$global:siteTemplatesListId = $null
$global:hubSitesListId = $null
$global:teamsTemplatesListId = $null
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

# Verifies installation of required PowerShell modules - throws error if a module is not installed
function VerifyModules {
    foreach ($module in $preReqModules.Keys) {
        $instModule = Get-InstalledModule -Name $module -ErrorAction:SilentlyContinue
        if ($null -eq $instModule) {
            throw("{0} module not installed. Install it with: Install-Module {0} -Scope CurrentUser" -f $module)
        }

        $minVersion = $preReqModules[$module]
        if ($null -ne $minVersion) {
            # Strip any prerelease suffix (e.g. 3.2.0-nightly) before comparing
            $installedVersion = [version](("$($instModule.Version)" -split '-')[0])
            if ($installedVersion -lt $minVersion) {
                throw("{0} version {1} is installed, but version {2} or newer is required. Update it with: Update-Module {0}" -f $module, $instModule.Version, $minVersion)
            }
        }
    }
}

# Create site and apply provisioning template
function CreateRequestsSharePointSite {
    try {
        Write-Host "### BESTILLINGSPORTALEN SPO SITE CREATION ###`nCreating Bestillingsportalen SharePoint site..." -ForegroundColor Yellow

        $site = Get-PnPTenantSite -Url $requestsSiteUrl -ErrorAction SilentlyContinue

        if (!$site) {
            $purgePerformed = $false

            # A soft-deleted site with the same URL blocks creation - New-PnPSite hangs
            # and eventually dies with an opaque NullReferenceException. Detect it and
            # offer to purge it from the tenant recycle bin.
            $deletedSite = Get-PnPTenantDeletedSite -Identity $requestsSiteUrl -ErrorAction SilentlyContinue
            if ($null -ne $deletedSite) {
                Write-Host "A deleted site with URL $requestsSiteUrl is in the tenant recycle bin - it blocks creating a new site on the same URL." -ForegroundColor Yellow
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

                Write-Host "An ACTIVE Microsoft 365 group with alias '$requestsSiteAlias' already exists: '$($activeGroup.displayName)', created $($activeGroup.createdDateTime), site: $groupSiteUrl." -ForegroundColor Yellow
                Write-Host "This is typically left behind by a previous partially failed site-creation attempt (the site ended up on a different URL). Check that the group/site contains nothing of value before deleting." -ForegroundColor Yellow
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
                    New-PnPSite -Type TeamSite -Title $parameters.requestsSiteName.Value -Alias $requestsSiteAlias -Description $parameters.requestsSiteDesc.Value -Owners $parameters.serviceAccountUPN.Value
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
        }
        else {
            Write-Host "Site already exists. Do you wish to re-apply the PnP provisioning template?" -ForegroundColor Yellow
            Write-Host "  y = re-apply template AND reset the configuration lists (Settings, Provisioning Types, Teams Templates etc.) to package defaults. Request data (Provisioning Requests / Guest Requests) is never touched." -ForegroundColor Cyan
            Write-Host "  n = leave the site and ALL list content untouched (only reads the list ids), then continue with Logic Apps / SPFx / other deploy steps" -ForegroundColor Cyan
            $overwrite = Read-Host " ( y / n )"
            if ($overwrite -ne "y") {
                $global:skipApplyTemplate = $true
                Write-Host "Template apply and list population will be skipped. Continuing with the rest of the deploy..." -ForegroundColor Yellow
            }
        }

        # Group-connected sites only grant access through group membership, and the
        # group owner is the SERVICE ACCOUNT (-Owners above) - not even the installing
        # SharePoint admin can open the site. The rest of the install connects to the
        # site AS the installing user (delegated auth) to apply the PnP template and
        # configure lists, so grant them site collection admin via the tenant admin
        # connection (works without site access for SharePoint admins). Additive - it
        # does not remove existing admins.
        if (-not [string]::IsNullOrEmpty($deployUser)) {
            Write-Host "Granting the installing user ($deployUser) site collection admin on the site..." -ForegroundColor Yellow
            Set-PnPTenantSite -Identity $requestsSiteUrl -Owners $deployUser
        }
        else {
            Write-Host "WARN: Could not determine the installing user (az ad signed-in-user failed) - if the next step fails with access denied, grant yourself site collection admin on $requestsSiteUrl via the SharePoint admin center and re-run." -ForegroundColor Yellow
        }
    }
    catch {
        RecordDeployStatus -Component "SharePoint site + PnP template" -Status 'FAILED' -Detail $_.Exception.Message
        throw('Failed to create the SharePoint site {0}', $_.Exception.Message)
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

            if ($global:upgrade) {
                # Preserve existing navigation in upgrade mode - apply schema/settings only
                Invoke-PnPSiteTemplate -Path (Join-Path $packageRootPath $templatePath)
            }
            else {
                Invoke-PnPSiteTemplate -Path (Join-Path $packageRootPath $templatePath) -ClearNavigation
            }

            Write-Host "Applied template" -ForegroundColor Green
        }
        
        # Skip the destructive list population when upgrading OR when the user chose to
        # keep the existing site content (the population below deletes and re-seeds the
        # Settings/Provisioning Types/Teams Templates/Time Zones lists from the package
        # defaults, wiping any customisations). List ids are still collected - they are
        # needed for the Logic App deployments.
        if ($global:upgrade -or $global:skipApplyTemplate) {
            if ($global:upgrade) {
                Write-Host "Running in Upgrade Mode - skipping list item population" -ForegroundColor Yellow
                Write-Host "For more information, see Upgrade.md" -ForegroundColor Cyan
            }
            else {
                Write-Host "Keeping existing site content - skipping list item population (only collecting list ids)" -ForegroundColor Yellow
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

        <# Create folders in Site Assets
         Try to get the folder first to see if it already exists - delete Site Request folder if it exists #>
        $siteRequestsFolder = Get-PnPFolder -Url "/$($parameters.managedPath.Value)/$requestsSiteAlias/SiteAssets/$provRequestsFolderName" -ErrorAction SilentlyContinue

        if ($null -ne $siteRequestsFolder) {
            Remove-PnPFolder -Name $provRequestsFolderName -Folder "SiteAssets" -Force
        }

        $folder = Add-PnPFolder -Name $provRequestsFolderName -Folder "$requestsSiteUrl/$siteAssetsListURL"
        
        $folder = Add-PnPFolder -Name $provTypesImageFolderName -Folder "$requestsSiteUrl/$siteAssetsListURL/$provRequestsFolderName"

        $folder = Add-PnPFolder -Name $provTypesIconFolderName -Folder "$requestsSiteUrl/$siteAssetsListURL/$provRequestsFolderName"

        Write-Host "Created folders in Site Assets" -ForegroundColor Green

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

        # Delete existing settings items
        $settingsItems = Get-PnPListItem -List $siteRequestsSettingsList

        foreach ($settingItem in $settingsItems) {
            Remove-PnPListItem -List $siteRequestsSettingsList -Identity $settingItem -Force
        }

        $siteRequestSettings = Import-Excel "$packageRootPath$settingsPath" -WorksheetName $provRequestSettingsWorksheetName
        foreach ($setting in $siteRequestSettings) {
            if ($setting.Title -eq "TenantURL") {
                $setting.Value = $global:tenantUrl
            }
            if ($setting.Title -eq "SPOManagedPath") {
                $setting.Value = $parameters.managedPath.Value
            }
            if ($setting.Title -eq "EnableSensitivityLabels") {
                If ($parameters.enableSensitivity.Value) {
                    $setting.Value = "true"
                }
            }
            $listItemCreationInformation = New-Object Microsoft.SharePoint.Client.ListItemCreationInformation
            $newItem = $siteRequestsSettingsList.AddItem($listItemCreationInformation)
            $newitem["Title"] = $setting.Title
            $newitem["Description"] = $setting.Description
            # Hide site classifications option if no site classifications were found in the tenant
            if ($null -eq $global:siteClassifications -and $setting.Title -eq "HideSiteClassifications") {
                $newItem["Value"] = "true"
            }
            else {
                $newitem["Value"] = $setting.Value
            }
            $newitem.Update()
            $context.ExecuteQuery()

        }

        # Hide blocked words field in settings list
        $field = $siteRequestsSettingsList.Fields.GetByInternalNameOrTitle("BlockedWordsValue")
        $field.SetShowInEditForm($false)
        $context.ExecuteQuery()
        $field.SetShowInNewForm($false)
        $context.ExecuteQuery()
        $field.SetShowInDisplayForm($false)
        $context.ExecuteQuery()

        Write-Host "Added settings to Provisioning Requests Settings list" -ForegroundColor Green

        # Adding provisioning types to Provisioning Types list
        $provTypesList = Get-PnPList $provTypesListName 
        $context.Load($provTypesList)
        $context.ExecuteQuery()

        # Delete existing provisioning types 
        $provTypeItems = Get-PnPListItem -List $provTypesList

        foreach ($provTypeItem in $provTypeItems) {
            Remove-PnPListItem -List $provTypesList -Identity $provTypeItem -Force
        }

        $provTypes = Import-Excel "$packageRootPath$settingsPath" -WorksheetName $provTypesWorksheetName
        foreach ($provType in $provTypes) {
            $listItemCreationInformation = New-Object Microsoft.SharePoint.Client.ListItemCreationInformation
            $newItem = $provTypesList.AddItem($listItemCreationInformation)
            $newitem["SortOrder"] = $provType.SortOrder
            $newitem["Title"] = $provType.Title
            $newitem["Description"] = $provType.Description
            $newitem["Allowed"] = $provType.Allowed
            $newitem["TemplateId"] = $provType.TemplateID
            $newitem["Image"] = "$requestsSiteUrl/$imageFolderUpload/$($provType.Image)"
            $newItem["Icon"] = "$requestsSiteUrl/$iconFolderUpload/$($provType.Icon)"
            $newitem["WebTemplateId"] = $provType.WebTemplateID
            $newitem["LearnVideoURL"] = $provType.LearnVideo
            $newItem["InternalTitle"] = $provType.InternalTitle
            $newItem["JoinHub"] = $provType.JoinHub
            $newitem["DefaultVisibility"] = $provType.DefaultVisibility
            $newitem.Update()
            $context.ExecuteQuery()
        }

        #Hide internal title field in provisioning types list
        $field = $provTypesList.Fields.GetByInternalNameOrTitle("InternalTitle")
        $field.SetShowInEditForm($false)
        $context.ExecuteQuery()
        $field.SetShowInNewForm($false)
        $context.ExecuteQuery()
        $field.SetShowInDisplayForm($false)
        $context.ExecuteQuery()

        Write-Host "Added provisioning types to Provisioning Types list" -ForegroundColor Green

        # Adding templates to Teams Templates list
        $teamsTemplatesList = Get-PnPList $teamsTemplatesListName
        $context.Load($teamsTemplatesList)
        $context.ExecuteQuery()

        $global:teamsTemplatesListId = $teamsTemplatesList.Id

        # Delete existing teams templates items
        $teamsTemplatesItems = Get-PnPListItem -List $teamsTemplatesList

        foreach ($teamsTemplateItem in $teamsTemplatesItems) {
            Remove-PnpListItem -List $teamsTemplatesList -Identity $teamsTemplateItem -Force
        }

        $teamsTemplates = Import-Excel "$packageRootPath$settingsPath" -WorksheetName $teamsTemplatesWorksheetName
        foreach ($template in $teamsTemplates) {
            If (!$parameters.IsEdu.Value -and ($template.BaseTemplateId -eq "educationStaff" -or $template.BaseTemplateId -eq "educationProfessionalLearningCommunity")) {
                # Tenant is not an EDU tenant  - do nothing
            }
            else {
                $listItemCreationInformation = New-Object Microsoft.SharePoint.Client.ListItemCreationInformation
                $newItem = $teamsTemplatesList.AddItem($listItemCreationInformation)
                $newItem["Title"] = $template.Title
                $newItem["TemplateId"] = $template.TemplateId
                $newItem["TeamId"] = $template.TeamId
                $newItem["Description"] = $template.Description
                $newItem["AdminCenterTemplate"] = $template.AdminCenterTemplate
                $newitem.Update()
                $context.ExecuteQuery()
            }
        }

        Write-Host "Added templates to Teams Templates list" -ForegroundColor Green

        # Adding time zones to the Time Zones list
        $timeZonesList = Get-PnPList $timeZonesListName
        $context.Load($timeZonesList)
        $context.ExecuteQuery()

        # Delete existing time zone items
        $timeZoneItems = Get-PnPListItem -List $timeZonesList

        foreach ($timeZoneItem in $timeZoneItems) {
            Remove-PnpListItem -List $timeZonesList -Identity $timeZoneItem -Force
        }

        $timeZones = Import-Excel "$packageRootPath$settingsPath" -WorksheetName $timeZonesWorksheetName
        foreach ($timeZone in $timeZones) {
            $listItemCreationInformation = New-Object Microsoft.SharePoint.Client.ListItemCreationInformation
            $newItem = $timeZonesList.AddItem($listItemCreationInformation)
            $newItem["Title"] = $timeZone.Title
            $newItem["TimeZoneId"] = $timeZone.TimeZoneId
            $newitem.Update()
            $context.ExecuteQuery()
        }
        
        Write-Host "Added time zones to Time Zones list" -ForegroundColor Green

        # Adding locales to the Locales list
        $localesList = Get-PnPList $localesListName
        $context.Load($localesList)
        $context.ExecuteQuery()
 
        # Delete existing locale items
        $localeItems = Get-PnPListItem -List $localesList
 
        foreach ($localeItem in $localeItems) {
            Remove-PnpListItem -List $localesList -Identity $localeItem -Force
        }
 
        $locales = Import-Excel "$packageRootPath$settingsPath" -WorksheetName $localesWorksheetName
        foreach ($locale in $locales) {
            $listItemCreationInformation = New-Object Microsoft.SharePoint.Client.ListItemCreationInformation
            $newItem = $localesList.AddItem($listItemCreationInformation)
            $newItem["Title"] = $locale.Title
            $newItem["LCID"] = $locale.LCID
            $newitem.Update()
            $context.ExecuteQuery()
        }
         
        Write-Host "Added locales to Locales list" -ForegroundColor Green

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
    param([Parameter(Mandatory = $true)][string]$Component)
    if ($LASTEXITCODE -ne 0) {
        RecordDeployStatus -Component $Component -Status 'FAILED' -Detail "az exited with code $LASTEXITCODE - see the error output above"
        Write-Host "$Component FAILED - continuing with the remaining components. See the summary at the end." -ForegroundColor Red
    }
    else {
        RecordDeployStatus -Component $Component -Status 'OK'
    }
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
# Service account validation
# The service account is used as site owner (New-PnPSite -Owners), for the delegated
# API connections and as the identity that posts the Teams welcome message - but
# nothing creates it. Fail early with a clear message instead of crashing midway
# through site creation when the account doesn't exist.
# Note: it no longer needs MFA disabled - that was only the sensitivity label ROPC flow.
# ---------------------------------------------------------------------------
function ValidateServiceAccount {
    $upn = $parameters.serviceAccountUPN.Value
    Write-Host "Validating service account $upn..." -ForegroundColor Yellow

    $saUserJson = az ad user show --id $upn 2>$null
    $saUser = if ($saUserJson) { $saUserJson | ConvertFrom-Json } else { $null }
    if ($null -eq $saUser) {
        RecordDeployStatus -Component "Service account" -Status 'FAILED' -Detail "'$upn' was not found in the tenant"
        throw "Service account '$upn' was not found in the tenant. Create the account (a standard user licensed for SharePoint, Exchange Online and Teams) before running the deployment, or correct serviceAccountUPN in parameters.json. Nothing has been changed in the environment."
    }
    $script:serviceAccountDisplayName = $saUser.displayName

    # Best-effort license check - warning only: the exact license requirements
    # are the customer's call.
    try {
        $licenseDetails = az rest --method get --url "https://graph.microsoft.com/v1.0/users/$upn/licenseDetails" 2>$null | ConvertFrom-Json
        $servicePlans = @($licenseDetails.value.servicePlans.servicePlanName)
        if ($servicePlans.Count -eq 0) {
            Write-Host "WARN: The service account has no licenses assigned. It needs SharePoint, Exchange Online and Teams licenses for the delegated API connections and notifications, and seeded Power Automate for the approval flow." -ForegroundColor Yellow
            RecordDeployStatus -Component "Service account" -Status 'WARNING' -Detail "'$upn' exists but has no licenses assigned"
            return
        }
        # The account must be able to own and activate the solution flow (guide step 5).
        # Frontline plans (FLOW_O365_S1) and unprovisioned viral trials (FLOW_P2_VIRAL
        # without _REAL) are not sufficient - seeded Power Automate from E1/E3/E5
        # (FLOW_O365_P1/P2/P3) or a standalone/per-user Flow plan is required.
        $flowPlans = @($servicePlans | Where-Object { $_ -match '^FLOW_' -and $_ -notin @('FLOW_O365_S1', 'FLOW_P2_VIRAL') })
        if ($flowPlans.Count -eq 0) {
            $foundFlowPlans = @($servicePlans | Where-Object { $_ -match '^FLOW_' }) -join ', '
            if (-not $foundFlowPlans) { $foundFlowPlans = 'none' }
            Write-Host "WARN: The service account has no usable Power Automate plan (found: $foundFlowPlans). Importing and activating the approval flow (guide step 5) requires seeded Power Automate (E1/E3/E5) or a standalone Flow plan - frontline (F1/F3) licenses are not sufficient." -ForegroundColor Yellow
            RecordDeployStatus -Component "Service account" -Status 'WARNING' -Detail "'$upn' has no usable Power Automate plan for the approval flow"
            return
        }
    }
    catch {}

    Write-Host "Service account verified: $($saUser.displayName) ($upn)" -ForegroundColor Green
    RecordDeployStatus -Component "Service account" -Status 'OK'
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
    Write-Host ("  Mode:                 {0}" -f $(if ($global:upgrade) { "UPGRADE of existing environment" } else { "FULL DEPLOYMENT" })) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Connected to:" -ForegroundColor Yellow
    Write-Host "    Entra ID tenant:    $($parameters.fullTenantName.Value) ($($parameters.tenantId.Value))"
    Write-Host "    Azure subscription: $($azContext.Subscription.Name) ($($azContext.Subscription.Id))"
    Write-Host "    Signed in as (Az):  $($azContext.Account.Id)"
    if (-not [string]::IsNullOrEmpty($deployUser)) {
        Write-Host "    Signed in as (CLI): $deployUser"
    }
    Write-Host "    SharePoint tenant:  $global:tenantUrl"
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
    WritePlanLine "SharePoint site" "$requestsSiteUrl (prompts before overwriting an existing site)" $SkipSharepointSite
    WritePlanLine "Azure resources" "Automation account '$automationAccountName', managed identity '$uamiName' (azureresources.bicep)" $SkipBicepDeploy
    WritePlanLine "App roles" "Graph/SharePoint roles on '$uamiName' + Automation system-assigned MI (only missing roles are added)"
    WritePlanLine "Runbooks" "ConfigureSpace, AddGuestToSite, GetSiteTemplates (content published from Source/Runbooks/)"
    if ($global:upgrade) {
        WritePlanLine "Logic Apps" "ProcessProvisionRequest + ProcessGuestRequest (upgrade set)" $SkipDeployARMTemplates
    }
    else {
        WritePlanLine "API connections" "5 connections (4 require manual authorisation afterwards)" ($SkipDeployARMTemplates -or $SkipDeployAPIConnections)
        WritePlanLine "Logic Apps" "9 logic apps" $SkipDeployARMTemplates
    }
    WritePlanLine "SPFx packages" "Build + publish to the tenant app catalog" $SkipSPFxDeploy
    WritePlanLine "Sensitivity labels" $(if ($parameters.enableSensitivity.Value) { "ENABLED (applied app-only with the automation account's managed identity - no service account needed)" } else { "disabled" })

    Write-Host ""
    Write-Host "############################################################" -ForegroundColor Magenta
    $confirm = Read-Host "Continue with this deployment? ( y / n )"
    if ($confirm -ne "y") {
        Write-Host "Deployment cancelled by user - nothing has been changed in the environment." -ForegroundColor Yellow
        exit 0
    }
    Write-Host "Confirmed - starting deployment..." -ForegroundColor Green
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
function DeployARMTemplates {
    try { 
        # Deploy ARM templates
        if (-not $SkipDeployAPIConnections) {
            Write-Host "Deploying api connections..." -ForegroundColor Yellow

            az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/apiconnections.json' --parameters "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "location=$($global:location)" --output none
            RecordAzResult "API connections"

            Write-Host "Finished deploying api connections..." -ForegroundColor Green
        }
        else {
            Write-Host "Skipping deployment of api connections..." -ForegroundColor Yellow
            RecordDeployStatus -Component "API connections" -Status 'SKIPPED'
        }
       
        Write-Host "Deploying logic apps..." -ForegroundColor Yellow

        Write-Host "ProcessGuests" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/processguests.json' --parameters  "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "location=$($global:location)" "uamiName=$uamiName" --output none
        RecordAzResult "Logic App: ProcessGuests"

        Write-Host "CheckSiteExists" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/checksiteexists.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "spoTenantName=$($parameters.spoTenantName.Value)" "location=$($global:location)" "uamiName=$uamiName" --output none
        RecordAzResult "Logic App: CheckSiteExists"
        
        Write-Host "ProcessProvisionRequest" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/processprovisionrequest.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "automationAccountName=$automationAccountName" "requestsSiteUrl=$requestsSiteUrl" "requestsListId=$global:requestsListId" "location=$($global:location)" "requestsSettingsListId=$global:requestsSettingsListId" "tenantName=$($parameters.spoTenantName.Value)" "serviceAccountUPN=$($parameters.serviceAccountUPN.value)" "uamiName=$uamiName" "spoRootSiteUrl=$global:tenantUrl" --output none
        RecordAzResult "Logic App: ProcessProvisionRequest"

        Write-Host "ProcessGuestRequest" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/processguestrequest.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "location=$($global:location)" "requestsSiteUrl=$requestsSiteUrl" "guestRequestsListId=$global:guestRequestsListId" "automationAccountName=$automationAccountName" "tenantName=$($parameters.spoTenantName.Value)" "uamiName=$uamiName" --output none
        RecordAzResult "Logic App: ProcessGuestRequest"

        Write-Host "SyncGroupSettings" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/syncgroupsettings.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "requestsSiteUrl=$requestsSiteUrl" "location=$($global:location)" "requestsSettingsListId=$global:requestsSettingsListId" "uamiName=$uamiName" --output none
        RecordAzResult "Logic App: SyncGroupSettings"

        Write-Host "GetSiteTemplates" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/getsitetemplates.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "requestsSiteUrl=$requestsSiteUrl" "location=$($global:location)" "siteTemplatesListId=$global:siteTemplatesListId" "automationAccountName=$automationAccountName" "uamiName=$uamiName" --output none
        RecordAzResult "Logic App: GetSiteTemplates"
        
        Write-Host "GetHubSites" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/gethubsites.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "tenantName=$($parameters.spoTenantName.Value)" "requestsSiteUrl=$requestsSiteUrl" "location=$($global:location)" "hubSitesListId=$global:hubSitesListId" "uamiName=$uamiName" "spoRootSiteUrl=$global:tenantUrl" --output none
        RecordAzResult "Logic App: GetHubSites"
        
        Write-Host "SyncLabels" -ForegroundColor Yellow
        
        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/synclabels.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "location=$($global:location)" "requestsSiteUrl=$requestsSiteUrl" "ipLabelsListId=$global:ipLabelsListId" "uamiName=$uamiName" --output none
        RecordAzResult "Logic App: SyncLabels"

        Write-Host "GetTeamsTemplates" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/getteamstemplates.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "requestsSiteUrl=$requestsSiteUrl" "location=$($global:location)" "teamsTemplatesListId=$global:teamsTemplatesListId" "tenantId=$($parameters.tenantId.Value)" "uamiName=$uamiName" --output none
        RecordAzResult "Logic App: GetTeamsTemplates"
        
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
        RecordDeployStatus -Component "Runbook runtime environment" -Status 'OK' -Detail "On '$runtimeEnvironmentName' (PowerShell 7.4). The portal's default Runbooks blade shows these as 'PowerShell 5.1' - a known display limitation, not a problem."
    }

    # CustomerSpecific is customer-owned and deliberately never overwritten, so deploy
    # cannot fix it. Environments upgraded from before 1.11.0 may still have it on the
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
    RecordAzResult "Runbooks + runtime environment (runbooks.bicep)"

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
        RecordAzResult "Logic App: ProcessProvisionRequest"

        Write-Host "ProcessGuestRequest" -ForegroundColor Yellow

        az deployment group create --resource-group $parameters.resourceGroupName.Value --subscription $parameters.subscriptionId.Value --template-file '../ARMTemplates/LogicApps/processguestrequest.json' --parameters "resourceGroupName=$($parameters.resourceGroupName.Value)" "subscriptionId=$($parameters.subscriptionId.Value)" "tenantId=$($parameters.tenantId.Value)" "location=$($global:location)" "requestsSiteUrl=$requestsSiteUrl" "guestRequestsListId=$global:guestRequestsListId" "automationAccountName=$automationAccountName" "tenantName=$($parameters.spoTenantName.Value)" "uamiName=$uamiName" --output none
        RecordAzResult "Logic App: ProcessGuestRequest"

        Write-Host "Finished deploying upgrade logic apps" -ForegroundColor Green
    }
    catch {
        throw('Failed to deploy logic apps in upgrade mode: {0}', $_.Exception.Message)
    }
}

# Connects PnP PowerShell to the given URL with interactive browser sign-in
# (delegated, as the account running the script). The deployment is attended by
# design - the script prompts throughout - so certificate/app-only auth is not
# supported. The token is cached in-session, so only the FIRST connection in a
# run shows a browser prompt; it is deliberately NOT persisted across sessions
# (-PersistLogin) to avoid leaving customer-tenant tokens on disk.
function ConnectPnP {
    param([Parameter(Mandatory = $true)][string]$Url)

    Connect-PnPOnline -Url $Url -ClientId $parameters.pnpAppId.Value -Interactive
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
    Write-Host "[INFO] Sending deployment pingback" -ForegroundColor Yellow

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
Write-Host "Loading PnP.PowerShell (must load before the Az module to avoid assembly conflicts)..." -ForegroundColor Yellow
Import-Module PnP.PowerShell -ErrorAction Stop

# Load Parameters from json file
$parametersListContent = Get-Content '.\parameters.json' -ErrorAction Stop

# Validate all the parameters.
Write-Host "Validating all the parameters from parameters.json" -ForegroundColor Yellow
$parameters = $parametersListContent | ConvertFrom-Json
if (-not(ValidateParameters)) {
    Write-Host "Invalid parameters found. Please update the parameters in the parameters.json with valid values and re-run the script." -ForegroundColor Red
    EXIT
}

Write-Host "Parameters are valid" -ForegroundColor Green

# Allow overriding the user-assigned managed identity name from parameters.json
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
$requestsSiteAlias = $parameters.requestsSiteName.Value -replace (' ', '')
$requestsSiteUrl = "https://$($parameters.spoTenantName.Value).sharepoint.com/$($parameters.managedPath.Value)/$requestsSiteAlias"

# Initialise connections - Azure Az/CLI. Both tools cache sessions across runs,
# so existing sessions matching the target tenant/subscription are offered for
# reuse instead of forcing a new MFA round trip on every run.

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

# Capture the signed-in user for the deployment pingback (best-effort; works in both deploy and upgrade mode)
try {
    $deployUser = az ad signed-in-user show --query userPrincipalName -o tsv 2>$null
}
catch {}

# Change the subscription
az account set --subscription $parameters.subscriptionId.Value

# Connect to PnP - the token is cached for the rest of this run, so only this
# first connection shows a browser prompt.
Write-Host "Launching PnP sign-in (a browser window will open - sign in with the account running this script)..." -ForegroundColor Yellow
ConnectPnP "https://$($parameters.spoTenantName.Value)-admin.sharepoint.com"
Write-Host "Connected to SPO" -ForegroundColor Green

# All sign-ins are done and nothing has been changed yet - validate the service
# account exists, then show the pre-flight summary and ask for confirmation
# before the first mutating step.
ValidateServiceAccount
ConfirmDeployment

if (-not $SkipSharepointSite) {
    CreateRequestsSharePointSite
    # Connect to the new site
    ConnectPnP $requestsSiteUrl
    ConfigureSharePointSite

    # Skip uploading assets in upgrade mode
    if (-not $global:upgrade) {
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

    # Ensure new runbooks (e.g. AddGuestToSite in 1.11.0) exist BEFORE the Logic Apps
    # that invoke them are deployed.
    DeployLocalRunbooks

    # Idempotent — grants Sites.FullControl.All + Group.ReadWrite.All to the
    # automation account's system-assigned managed identity if not already
    # present. Needed by AddGuestToSite for Add-PnPMicrosoft365GroupMember/Owner.
    # Pre-1.11.0 deploys may have skipped this in upgrade mode.
    AssignManagedIdentityPermissions

    # The logic apps reference the user-assigned managed identity, which is created by
    # azureresources.bicep (skipped in upgrade mode). Installations deployed before the
    # managed identity migration must run a full deploy first - fail early with a clear
    # message instead of a cryptic ARM error. See Managed-identity-migration.md.
    $uamiExists = az identity show --resource-group $parameters.resourceGroupName.Value --name $uamiName --query principalId --output tsv 2>$null
    if ([string]::IsNullOrEmpty($uamiExists)) {
        throw "User-assigned managed identity '$uamiName' was not found in resource group '$($parameters.resourceGroupName.Value)'. Run a full deployment (without -Upgrade) once to migrate to managed identity before using upgrade mode. See Managed-identity-migration.md."
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

    SendDeployPingback

    WriteDeploymentReport

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
    Write-Host "Creating resource group $($parameters.resourceGroupName.Value)..." -ForegroundColor Yellow
    New-AzResourceGroup -Name $parameters.resourceGroupName.Value -Location $global:location | Out-Null
    Write-Host "Created resource group" -ForegroundColor Green
    RecordDeployStatus -Component "Resource group" -Status 'OK'
}
else {
    Write-Host "Skipping resource group creation" -ForegroundColor Yellow
    RecordDeployStatus -Component "Resource group" -Status 'SKIPPED'
}

Write-Host "Deploying Azure resources" -ForegroundColor Yellow

if (-not $SkipBicepDeploy) {
    Write-Host "Deploying automation account and managed identity..." -ForegroundColor Yellow
    az deployment group create --subscription $parameters.subscriptionId.Value --resource-group $parameters.resourceGroupName.Value --template-file "../ARMTemplates/azureresources.bicep" --parameters "tenantId=$($parameters.tenantId.Value)" "logoUrl=$($parameters.siteLogoPath.Value)" "uamiName=$uamiName" --output none
    RecordAzResult "Azure resources (bicep: Automation, UAMI)"
    if ($LASTEXITCODE -ne 0) {
        # Everything after this point (permissions, runbooks, logic apps) depends on
        # these resources - no point continuing.
        throw "azureresources.bicep deployment failed - see the error output above. Fix the cause and re-run the script."
    }
    AssignManagedIdentityPermissions
    AssignUamiPermissions
    DeployLocalRunbooks
    Write-Host "Finished deploying key vault, automation account and managed identity..." -ForegroundColor Green
}
else {
    Write-Host "Skipping azureresources.bicep deployment" -ForegroundColor Yellow
    RecordDeployStatus -Component "Azure resources (bicep: Key Vault, Automation, UAMI)" -Status 'SKIPPED'
    # The logic apps and API connections still need the app roles on the user-assigned
    # managed identity - keep them in sync even when the bicep deployment is skipped.
    AssignUamiPermissions
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

SendDeployPingback

WriteDeploymentReport

Write-Host ""
Write-Host "Remaining manual steps (details in Deployment-guide.md):" -ForegroundColor Cyan
Write-Host "  1. Authorise the delegated API connections with the service account - run ./Authorize-ApiConnections.ps1 for a guided flow, or use the Azure Portal ('Autorisere API-tilkoblinger' under step 3 in the guide)." -ForegroundColor Cyan
Write-Host "  2. NEW environment only: import the Power Automate flows as the service account from Source/Flows/Bestillingsportalen-Flows_unmanaged.zip (step 5 in the guide)." -ForegroundColor Cyan
Write-Host "  3. Configure the approval process, then activate and share the flows as the service account (steps 4-6 in the guide)." -ForegroundColor Cyan
Write-Host "  4. Run the supporting Logic Apps once and set up the admin group (steps 7-9 in the guide)." -ForegroundColor Cyan
Write-Host ""

if ((GetFailedDeployComponents).Count -gt 0) {
    Write-Host "### DEPLOYMENT COMPLETED WITH ERRORS - SEE SUMMARY ABOVE ###" -ForegroundColor Red
    exit 1
}

Write-Host "### DEPLOYMENT COMPLETED SUCCESSFULLY ###" -ForegroundColor Green
