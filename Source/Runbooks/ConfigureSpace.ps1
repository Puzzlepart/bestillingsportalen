#Runbook to configure collaboration spaces post provisioning - for use with the Bestillingsportalen solution
[CmdletBinding()] 
Param
(
    [Parameter (Mandatory = $false)]
    [string] $groupId,
    [string] $siteUrl,
    [string] $spaceType,
    [string] $spaceTypeInternal,
    [string] $externalSharing,
    [string] $owners,
    [string] $members,
    [string] $visitors,
    [string] $visibility,
    [string] $classification,
    [string] $joinHub,
    [string] $hubSiteId,
    [string] $timeZoneId,
    [string] $lcid,
    [bool] $enableAllowAccessRequests,
    [string] $defaultExternalSharingSetting,
    [int] $storageQuota,
    [int] $storageQuotaWarning,
    [bool] $syncHubPermissions,
    [bool] $disableDocSync,
    [string] $retentionLabel,
    [string] $sensitivityLabel,
    [string] $sensitivityLabelLibrary,
    [string] $featuresToActivate,
    [string] $applyPnPTemplate,
    [string] $pnpTemplateUrl,
    [string] $themeName,
    [string] $siteTemplateTitle,
    [string] $siteCollectionAdmins,
    [string] $siteDesignId,
    [string] $spaceImage,
    [bool] $internalChannel,
    [bool] $readOnlyGroup,
    [string] $defaultReadOnlyGroup,
    $metadata,
    [string] $parentSiteUrl,
    # Only used by the sensitivity label step - see SetSensitivityLabel.
    # enableSensitivityLabels mirrors the EnableSensitivityLabels item in the
    # 'Provisioning Request Settings' list and is the admin kill-switch for the feature.
    # Passed as a string because the logic app interpolates its boolean variable.
    [string] $keyVaultName,
    [string] $tenantId,
    [string] $enableSensitivityLabels
)

# Fail fast inside each step. Without this, non-terminating PnP errors slip past every
# catch block below and the run reports success while individual steps did nothing.
# Invoke-Step turns each step's failure back into "record it and carry on", so the
# accumulate-and-continue behaviour of this runbook is preserved.
$ErrorActionPreference = 'Stop'

# The SharePoint host name, not just the tenant prefix: parsing on the first '.' broke
# on anything that is not exactly https://tenant.sharepoint.com/...
$siteUri = [System.Uri]$siteUrl
$tenantName = $siteUri.Host.Split('.')[0]
$adminUrl = "https://$tenantName-admin.sharepoint.com"

# Several parameters arrive as strings from the logic app because it interpolates its
# own boolean variables ("True"/"False"). `if ($someString)` is true for any non-empty
# string, so "false" used to switch features ON.
function ConvertTo-Bool {
    param([string] $Value)
    return $Value -iin @('true', '1')
}

$externalSharingEnabled = ConvertTo-Bool $externalSharing
$joinHubEnabled = ConvertTo-Bool $joinHub
$applyPnPTemplateEnabled = ConvertTo-Bool $applyPnPTemplate

# Global variables for error tracking
$script:hasErrors = $false
$script:errorMessages = @()
$script:stepResults = @()

# Connect helpers. Each step connects to the context it needs rather than relying on
# whatever the previous step happened to leave behind - tenant-admin cmdlets such as
# Set-PnPTenantSite used to be called while the connection pointed at the site itself.
function Connect-Admin {
    Connect-PnPOnline -Url $adminUrl -ManagedIdentity
}

function Connect-Site {
    Connect-PnPOnline -Url $siteUrl -ManagedIdentity
}

# Function to handle errors and update the provisioning request status
function Set-SpaceCreationFailed {
    param(
        [string]$FunctionName,
        [string]$ErrorMessage
    )

    $script:hasErrors = $true
    $script:errorMessages += "$FunctionName failed: $ErrorMessage"

    # -ErrorAction Continue because $ErrorActionPreference is Stop for the script - we
    # want this on the error stream for the job log, not as a terminating error.
    Write-Error "[$FunctionName] $ErrorMessage" -ErrorAction Continue
}

# Runs one configuration step. A failing step is recorded and the run continues, so a
# bad theme name does not stop the retention label from being applied. The collected
# results are also what the caller reads back as the run's outcome.
function Invoke-Step {
    param([Parameter(Mandatory = $true)][string] $Name)

    Write-Output ""
    Write-Output "--- $Name ---"
    try {
        & $Name
        $script:stepResults += [pscustomobject]@{ Step = $Name; Status = 'Succeeded'; Error = $null }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName $Name -ErrorMessage $_.Exception.Message
        $script:stepResults += [pscustomobject]@{ Step = $Name; Status = 'Failed'; Error = $_.Exception.Message }
    }
}

# The name of the default document library varies with the site's language - the old
# hardcoded "Dokumenter" failed on every non-Norwegian site.
function Get-DefaultDocumentLibrary {
    $library = Get-PnPList | Where-Object {
        $_.BaseTemplate -eq 101 -and $_.IsDefaultDocumentLibrary -eq $true
    } | Select-Object -First 1

    if ($null -eq $library) {
        # Fall back to the well-known server-relative names before giving up.
        foreach ($candidate in @('Shared Documents', 'Dokumenter', 'Documents')) {
            $library = Get-PnPList -Identity $candidate -ErrorAction SilentlyContinue
            if ($null -ne $library) { break }
        }
    }

    if ($null -eq $library) {
        throw "Could not find the default document library on $siteUrl"
    }

    return $library
}

# Update-ProvisioningRequestStatus used to live here. It never updated anything - it
# only logged, because the actual list update belongs to the logic app. Write-StepSummary
# plus the thrown exception message now serve that purpose without the misleading name.

function SetSiteLogo {
    if ($spaceImage -eq "") {
        Write-Output "No space image supplied - skipping"
        return
    }

    Connect-Site

    Write-Output "Adding site logo (convert base64 to image)"
    $logoFileName = "$groupId.png"
    $logoPath = Join-Path $env:TEMP $logoFileName

    $bytes = [System.Convert]::FromBase64String($spaceImage)
    [System.IO.File]::WriteAllBytes($logoPath, $bytes)

    Write-Output "Setting group logo"
    Set-PnPMicrosoft365Group -Identity $groupId -GroupLogoPath $logoPath

    Write-Output "Adding logo to site assets library"

    $web = Get-PnPWeb
    # Probing for existence, so a miss here is expected and stays silent.
    $siteAssets = Get-PnPList -Identity "SiteAssets" -ErrorAction SilentlyContinue
    if ($null -eq $siteAssets) {
        $web.Lists.EnsureSiteAssetsLibrary()
        Invoke-PnPQuery
    }

    Add-PnPFile -Path $logoPath -Folder "SiteAssets" | Out-Null
    $siteAssetsLogoPath = "$($web.ServerRelativeUrl)/SiteAssets/$($logoFileName)"
    Set-PnPWebHeader -SiteLogoUrl $siteAssetsLogoPath -SiteThumbnailUrl $siteAssetsLogoPath | Out-Null
    Write-Output "Finished setting site logo"
}

function AddOwners {
    if ($spaceTypeInternal -in "Office 365 Group", "Project") { return }
    if ($owners -eq "") { return }

    Connect-Site
    Write-Output "Updating SP owners group"
    $group = Get-PnPGroup -AssociatedOwnerGroup
    ForEach ($owner in $owners -split ",") {
        Write-Output("Adding '$owner' to Owners")
        Add-PnPGroupMember -LoginName $owner -Identity $group
    }
}

function AddMembers {
    if ($members -eq "" -or $spaceTypeInternal -in "Office 365 Group", "Project") { return }

    Connect-Site
    Write-Output "Updating SP members group"
    # Fetched once - this used to be re-read on every iteration.
    $group = Get-PnPGroup -AssociatedMemberGroup
    ForEach ($member in $members -split ",") {
        Write-Output("Adding '$member' to Members")
        Add-PnPGroupMember -LoginName $member -Identity $group
    }

    Write-Output "Finished updating SP members group"
}

function AddVisitors {
    if ($visitors -eq "") { return }

    Connect-Site
    Write-Output "Updating SP visitors group"
    $group = Get-PnPGroup -AssociatedVisitorGroup
    ForEach ($visitor in $visitors -split ",") {
        Write-Output("Adding '$visitor' to Visitors")
        Add-PnPUserToGroup -LoginName $visitor -Identity $group
    }

    Write-Output "Finished updating SP visitors group"
}

function AddReadOnlyGroup {
    if (-not $readOnlyGroup -or $defaultReadOnlyGroup -eq "") { return }

    Connect-Site
    Write-Output "Updating SP visitors group with read-only group '$defaultReadOnlyGroup'"
    $group = Get-PnPGroup -AssociatedVisitorGroup
    Add-PnPGroupMember -Group $group -LoginName $defaultReadOnlyGroup
    Write-Output "Finished updating SP visitors group"
}

function AddSiteCollectionAdmins {
    # The logic app never sends this parameter, so it is normally empty. Guard it
    # explicitly - "" -split "," yields one empty element, which used to be passed
    # straight to Add-PnPSiteCollectionAdmin.
    if ($spaceTypeInternal -in "Office 365 Group", "Project") { return }
    if ([string]::IsNullOrWhiteSpace($siteCollectionAdmins)) {
        Write-Output "No site collection administrators supplied - skipping"
        return
    }

    Connect-Site
    Write-Output "Adding Site Collection Administrators"
    ForEach ($sca in $siteCollectionAdmins -split ",") {
        if ([string]::IsNullOrWhiteSpace($sca)) { continue }
        Add-PnPSiteCollectionAdmin -Owners $sca.Trim()
    }
    Write-Output "Finished adding Site Collection Administrators"
}

function SetExternalSharing {
    if (-not $externalSharingEnabled) {
        Write-Output "External sharing not requested - skipping"
        return
    }

    # Set-PnPTenantSite is a tenant-admin cmdlet.
    Connect-Admin

    Write-Output "External sharing is required - configuring sharing settings"

    Switch ($defaultExternalSharingSetting) {
        "NewExistingGuests" {
            Set-PnPTenantSite -Url $siteUrl -SharingCapability ExternalUserSharingOnly
        }
        "Anyone" {
            Set-PnPTenantSite -Url $siteUrl -SharingCapability ExternalUserAndGuestSharing
        }
        "ExistingGuests" {
            Set-PnPTenantSite -Url $siteUrl -SharingCapability ExistingExternalUserSharingOnly
        }
        default {
            Write-Output "Unknown DefaultExternalSharingSetting '$defaultExternalSharingSetting' - leaving the site's sharing capability unchanged"
        }
    }

    Write-Output "Finished configuring sharing settings"
}

function SetAccessRequestSettings {
    #Disable access requests if visibility set to private
    if (-not ($visibility -eq "Private" -and $enableAllowAccessRequests -eq $false)) { return }

    Connect-Site
    Write-Output "Disabling access requests"
    $ctx = Get-PnPContext
    $ctx.Web.RequestAccessEmail = ""
    $ctx.ExecuteQuery()
    Write-Output "Finished disabling access requests"
}

function SetSiteClassification {
    if ($spaceTypeInternal -in "Office 365 Group", "Project") { return }
    if ($classification -eq "") { return }

    Connect-Site
    Write-Output "Setting classification '$classification'"
    Set-PnPSite -Classification $classification
    Write-Output "Finished setting classification"
}

function JoinOrRegisterHubSite {
    # Both branches are tenant-admin operations.
    Connect-Admin

    if ($joinHubEnabled -and $spaceTypeInternal -ne "Hub Site") {
        Write-Output "Joining hub site $hubSiteId"

        $hubSite = Get-PnPHubSite | Where-Object SiteId -eq $hubSiteId | Select-Object -Property SiteUrl
        if ($null -eq $hubSite) {
            throw "Hub site with id '$hubSiteId' was not found in the tenant."
        }

        Add-PnPHubSiteAssociation -Site $siteUrl -HubSite $hubSite.SiteUrl
        Write-Output "Finished joining hub site"
        return
    }

    if ($spaceTypeInternal -eq "Hub Site") {
        Write-Output "Registering site as a hub"
        Register-PnPHubSite -Site $siteUrl
        Write-Output "Finished registering site as a hub"

        if ($syncHubPermissions) {
            Write-Output "Enabling hub permissions sync"
            Set-PnPHubSite -Identity $siteUrl -EnablePermissionsSync
            Write-Output "Finished enabling hub permissions sync"
        }
        return
    }

    Write-Output "Not joining or registering a hub site"
}

function SetRegionalSettings {
    Connect-Site

    #Set regional settings for the site
    Write-Output "Setting regional settings (lcid $lcid, time zone $timeZoneId)"
    $web = Get-PnPWeb -Includes RegionalSettings, RegionalSettings.TimeZones
    $timeZone = $web.RegionalSettings.TimeZones | Where-Object { $_.Id -eq $timeZoneId }
    if ($null -eq $timeZone) {
        throw "Time zone id '$timeZoneId' was not found among the web's available time zones."
    }
    $web.RegionalSettings.LocaleId = $lcid
    $web.RegionalSettings.TimeZone = $timeZone
    $web.Update()
    Invoke-PnPQuery
    Write-Output "Finished setting regional settings"
}

function SetStorageQuota {
    if ($storageQuota -eq 0 -or $storageQuotaWarning -eq 0) { return }

    Connect-Admin
    Write-Output "Setting site storage quota"
    Set-PnPTenantSite -Url $siteUrl -StorageMaximumLevel $storageQuota -StorageWarningLevel $storageQuotaWarning
    Write-Output "Finished setting storage quota"
}

function DisableDocumentSync {
    if (-not $disableDocSync) { return }

    Connect-Site
    $list = Get-DefaultDocumentLibrary
    Write-Output "Disabling sync option in '$($list.Title)' library"

    #Exclude List or Library from Sync
    $list.ExcludeFromOfflineClient = $true
    $list.Update()
    Invoke-PnPQuery

    Write-Output "Finished disabling sync option"
}

function SetRetentionLabel {
    if ($retentionLabel -eq "") { return }

    Connect-Site
    $list = Get-DefaultDocumentLibrary
    Write-Output "Setting retention label $retentionLabel on '$($list.Title)' library"

    Set-PnPLabel -List $list -Label $retentionLabel

    Write-Output "Finished setting retention label"
}

# Reads the sensitivity labels currently assigned to a Microsoft 365 group.
# Invoke-PnPGraphMethod reuses the managed identity token from the PnP connection.
function Get-GroupAssignedLabelId {
    param([Parameter(Mandatory = $true)][string] $GroupId)

    $response = Invoke-PnPGraphMethod -Url ('v1.0/groups/' + $GroupId + '?$select=assignedLabels') -Method Get
    return @($response.assignedLabels | ForEach-Object { $_.labelId })
}

# Polls until the label shows up on the group, or the timeout expires. Applying a
# container label is asynchronous, so a single read straight after the write is not
# conclusive either way.
function Test-GroupLabelApplied {
    param(
        [Parameter(Mandatory = $true)][string] $GroupId,
        [Parameter(Mandatory = $true)][string] $LabelId,
        [int] $TimeoutSeconds = 60
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        try {
            if ((Get-GroupAssignedLabelId -GroupId $GroupId) -contains $LabelId) {
                return $true
            }
        }
        catch {
            Write-Output "Could not read assignedLabels on group $GroupId : $($_.Exception.Message)"
        }

        if ((Get-Date) -ge $deadline) { return $false }
        Start-Sleep -Seconds 15
    }
}

# Delegated fallback for group-connected containers.
#
# Microsoft Graph still does not support application permissions for
# PATCH /groups/{id} with assignedLabels (re-verified August 2026, including with
# Group.ManageProtection.All, which exists as an app role but is delegated-only for
# this property). A service account without MFA plus a ROPC token is therefore the
# only way, and the credentials live in Key Vault.
#
# This used to be a 12-action scope in the ProcessProvisionRequest logic app, where
# the password, the client secret and the resulting access token were all visible in
# the run history. Keeping it here means none of them leave this process.
function Set-GroupSensitivityLabelDelegated {
    param(
        [Parameter(Mandatory = $true)][string] $GroupId,
        [Parameter(Mandatory = $true)][string] $LabelId
    )

    if ($keyVaultName -eq "" -or $tenantId -eq "") {
        throw "Delegated sensitivity label flow needs both keyVaultName and tenantId, but at least one was empty."
    }

    # PnP.PowerShell is already loaded at this point, so Az loads second - the order
    # that avoids the Microsoft.Extensions assembly conflict between the two modules.
    Connect-AzAccount -Identity | Out-Null

    $appId        = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name 'appid' -AsPlainText
    $appSecret    = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name 'appSecret' -AsPlainText
    $saUserName   = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name 'sausername' -AsPlainText
    $saPassword   = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name 'sapassword' -AsPlainText

    if ([string]::IsNullOrWhiteSpace($saUserName) -or [string]::IsNullOrWhiteSpace($saPassword)) {
        throw "Service account credentials are missing from Key Vault '$keyVaultName'. Sensitivity labels are enabled but 'sausername'/'sapassword' have no value - see Sensitivity-labels.md."
    }

    # Invoke-RestMethod form-encodes a hashtable body, so no manual URL encoding.
    $tokenResponse = Invoke-RestMethod -Method Post `
        -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body @{
            client_id     = $appId
            client_secret = $appSecret
            grant_type    = 'password'
            username      = $saUserName
            password      = $saPassword
            scope         = 'https://graph.microsoft.com/.default'
        }

    $ownerAdded = $false
    try {
        # The service account needs write access to the group, which for a plain
        # licensed user means being an owner.
        try {
            Add-PnPMicrosoft365GroupOwner -Identity $GroupId -Users $saUserName
            $ownerAdded = $true
            Write-Output "Added service account as temporary owner of group $GroupId"
        }
        catch {
            # Most likely already an owner. Deliberately leave $ownerAdded false so we
            # never remove an owner we did not add ourselves.
            Write-Output "Could not add service account as owner (may already be one): $($_.Exception.Message)"
        }

        $patchBody = @{ assignedLabels = @(@{ labelId = $LabelId }) } | ConvertTo-Json -Depth 4
        $maxAttempts = 6

        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            try {
                # Retry instead of a fixed wait: the ownership above needs a moment to
                # propagate, and the PATCH returns 403 until it has.
                Invoke-RestMethod -Method Patch -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId" `
                    -Headers @{ Authorization = "Bearer $($tokenResponse.access_token)" } `
                    -ContentType 'application/json' -Body $patchBody | Out-Null

                Write-Output "Applied sensitivity label to group $GroupId on attempt $attempt"
                return
            }
            catch {
                if ($attempt -eq $maxAttempts) {
                    throw "Failed to apply sensitivity label to group $GroupId after $maxAttempts attempts: $($_.Exception.Message)"
                }

                Write-Output "Attempt $attempt of $maxAttempts failed ($($_.Exception.Message)) - retrying in 15 seconds"
                Start-Sleep -Seconds 15
            }
        }
    }
    finally {
        # Always give the ownership back, including on failure. The logic app only did
        # this on success, so a failed labelling left the service account as a
        # permanent owner of the group.
        if ($ownerAdded) {
            try {
                Remove-PnPMicrosoft365GroupOwner -Identity $GroupId -Users $saUserName
                Write-Output "Removed service account from owners of group $GroupId"
            }
            catch {
                Write-Output "WARNING: could not remove service account from owners of group $GroupId : $($_.Exception.Message). Remove it manually."
            }
        }
    }
}

# Applies the Purview container label. Runs before the settings the label governs
# (privacy, external sharing, unmanaged devices), because the label overrides them.
#
# Requires the tenant admin connection - Set-PnPTenantSite is a tenant-admin cmdlet.
function SetSensitivityLabel {
    if ($sensitivityLabel -eq "") { return }

    # Respect the admin kill-switch even if a request carries a label id anyway
    # (hand-edited list item, stale front-end).
    if ($enableSensitivityLabels -ne "" -and $enableSensitivityLabels -inotin @("true", "1")) {
        Write-Output "Sensitivity labels are disabled (EnableSensitivityLabels = '$enableSensitivityLabels') - skipping label $sensitivityLabel"
        return
    }

    Connect-Admin

    Write-Output "Setting sensitivity label $sensitivityLabel (app-only attempt)"
    try {
        Set-PnPTenantSite -Identity $siteUrl -SensitivityLabel $sensitivityLabel
        Write-Output "Set-PnPTenantSite returned without error"
    }
    catch {
        # Deliberately swallowed: the delegated fallback below is the real path when
        # app-only is not allowed. Only an unlabelled group at the end is a failure.
        Write-Output "App-only label call failed: $($_.Exception.Message)"
    }

    if ([string]::IsNullOrWhiteSpace($groupId)) {
        # No group behind the site, so the label lives on the site alone and
        # app-only is documented to work. Nothing to verify against a group.
        Write-Output "Site is not group-connected - finished setting sensitivity label"
        return
    }

    # Set-PnPTenantSite can report success without the label ever being applied on
    # group-connected sites (pnp/powershell#4917), so no exception is not proof.
    # Read it back off the group before deciding whether the fallback is needed.
    if (Test-GroupLabelApplied -GroupId $groupId -LabelId $sensitivityLabel) {
        Write-Output "Label confirmed on group $groupId - app-only path was sufficient"
        return
    }

    Write-Output "Label not present on group $groupId after the app-only attempt - using the delegated flow"
    Set-GroupSensitivityLabelDelegated -GroupId $groupId -LabelId $sensitivityLabel

    if (-not (Test-GroupLabelApplied -GroupId $groupId -LabelId $sensitivityLabel)) {
        throw "Sensitivity label $sensitivityLabel was not present on group $groupId after the delegated flow completed."
    }

    Write-Output "Label confirmed on group $groupId - finished setting sensitivity label"
}

function SetSensitivityLabelLibrary {
    if ($sensitivityLabelLibrary -eq "") { return }

    Connect-Site
    $list = Get-DefaultDocumentLibrary
    Write-Output "Setting sensitivity label $sensitivityLabelLibrary on '$($list.Title)' library"

    Set-PnPList -Identity $list -DefaultSensitivityLabelForLibrary $sensitivityLabelLibrary

    Write-Output "Finished setting sensitivity label on the library"
}

function ActivateFeatures {
    if ($featuresToActivate -eq "") { return }

    Connect-Site
    Write-Output "Activating features"

    $ctx = Get-PnPContext
    $site = $ctx.Site
    $ctx.Load($site)
    $ctx.ExecuteQuery()

    $web = $ctx.Web
    $ctx.Load($web)
    $ctx.ExecuteQuery()

    $force = $true

    # Check if we are activating a web feature - need to activate the push notifications feature first to prevent an error
    if ($featuresToActivate.ToLower().Contains('web')) {

        $pushNotificationsFeatureId = "41e1d4bf-b1a2-47f7-ab80-d5d6cbba3092"

        try {
            Write-Output "Pre-activating push notifications feature"
            $web.Features.Add($pushNotificationsFeatureId, $force, [Microsoft.SharePoint.Client.FeatureDefinitionScope]::None)
            $ctx.ExecuteQuery()
            Write-Output "Push notifications feature activated successfully"
        }
        catch {
            Write-Output "Warning: Could not activate push notifications feature: $($_.Exception.Message)"
            # Continue anyway - this is not critical
        }
    }

    ForEach ($feature in $featuresToActivate -split ",") {
        $featureId = $feature.Substring($feature.IndexOf(':') + 1)

        If ($feature.ToLower().StartsWith("web")) {
            Write-Output "Activating web feature $featureId"

            $web.Features.Add($featureId, $force, [Microsoft.SharePoint.Client.FeatureDefinitionScope]::None)
            $ctx.ExecuteQuery()

            Write-Output "Activated web feature $featureId"
        }

        If ($feature.ToLower().StartsWith("site")) {
            Write-Output "Activating site feature $featureId"

            $site.Features.Add($featureId, $force, [Microsoft.SharePoint.Client.FeatureDefinitionScope]::Farm)
            $ctx.ExecuteQuery()

            Write-Output "Activated site feature $featureId"
        }
    }

    Write-Output "Finished activating features"
}

function ApplyPnPTemplate {
    if (-not $applyPnPTemplateEnabled) { return }

    Connect-Site
    Write-Output "Applying PnP template from $pnpTemplateUrl"

    $maxRetries = 3

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            Write-Output "Attempt $attempt of $maxRetries to apply PnP template"
            Invoke-PnPSiteTemplate -Path $pnpTemplateUrl -ClearNavigation
            Write-Output "Finished applying PnP template"
            return
        }
        catch {
            if ($attempt -eq $maxRetries) {
                throw "Failed to apply PnP template after $maxRetries attempts: $($_.Exception.Message)"
            }

            $waitTime = 10 * $attempt
            Write-Output "Error applying PnP template (attempt $attempt): $($_.Exception.Message). Retrying in $waitTime seconds."
            Start-Sleep -Seconds $waitTime
        }
    }
}

function ApplyTheme {
    if ($themeName -eq "") { return }

    Connect-Site
    Write-Output "Applying $themeName theme"
    Set-PnPWebTheme -Theme $themeName
    Write-Output "Finished applying theme"
}

function ApplySiteDesign {
    # Reapply site design if we have applied a PnP template
    if (-not $applyPnPTemplateEnabled -or [string]::IsNullOrWhiteSpace($siteDesignId)) { return }

    Connect-Admin
    Write-Output "Applying site design $siteDesignId"
    Invoke-PnPSiteDesign -Identity $siteDesignId -WebUrl $siteUrl
    Write-Output "Finished applying site design"
}

function SetMetadata {
    if ($null -eq $metadata -or $metadata -eq "") {
        Write-Output "No metadata provided"
        return
    }

    Connect-Site

    # Convert metadata to string if it's not already
    if ($metadata -is [string]) {
        $metadataString = $metadata
    }
    else {
        $metadataString = $metadata | ConvertTo-Json -Compress -Depth 10
    }

    $metadataObject = $metadataString | ConvertFrom-Json
    Write-Output "Successfully parsed metadata JSON"

    # Handle propertyBagProps
    if ($null -eq $metadataObject.propertyBagProps) {
        Write-Output "No propertyBagProps in metadata"
        return
    }

    Write-Output "Processing propertyBagProps"

    # NoScript is already disabled for the whole configuration run (see DisableNoScript/EnableNoScript)
    foreach ($prop in $metadataObject.propertyBagProps) {
        $propName = $prop.name
        $propValue = $prop.value
        if ($null -eq $propName -or $null -eq $propValue) { continue }

        Write-Output "Adding property bag value for '$propName'"

        if ($prop.indexed -eq $true) {
            Write-Output "Setting property '$propName' as indexed"
            Set-PnPPropertyBagValue -Key $propName -Value $propValue -Indexed
        }
        else {
            Set-PnPPropertyBagValue -Key $propName -Value $propValue
        }
    }

    Write-Output "Finished processing metadata"
}

function UpdateParentSite {
    if ([string]::IsNullOrWhiteSpace($parentSiteUrl)) {
        Write-Output "No parent site specified, skipping UpdateParentSite"
        return
    }

    Write-Output "Parent site specified: $parentSiteUrl"

    Connect-Site
    $currentSite = Get-PnPSite -Includes Id, Url
    $currentWeb = Get-PnPWeb
    $currentSiteId = $currentSite.Id.ToString()
    $currentSiteTitle = $currentWeb.Title
    $currentSiteUrl = $currentSite.Url

    $hubSiteUrl = ""
    $hubSiteTitle = ""

    if (-not [string]::IsNullOrWhiteSpace($hubSiteId)) {
        Connect-Admin
        # Probing - a missing hub site is not fatal here, we just skip the hub update.
        $hubSiteInfo = Get-PnPHubSite -Identity $hubSiteId -ErrorAction SilentlyContinue

        if ($null -ne $hubSiteInfo) {
            $hubSiteUrl = $hubSiteInfo.SiteUrl
            $hubSiteTitle = $hubSiteInfo.Title
            Write-Output "Hub site information retrieved: $hubSiteTitle ($hubSiteUrl)"
        }
    }

    $childProjectObject = @{
        key          = $currentSiteId
        SiteId       = $currentSiteId
        Title        = $currentSiteTitle
        Path         = $currentSiteUrl
        HubSiteId    = $hubSiteId
        HubSiteUrl   = $hubSiteUrl
        HubSiteTitle = $hubSiteTitle
    }

    Write-Output "Child project data: $(ConvertTo-Json @($childProjectObject) -Compress)"

    # Merges $childProjectObject into an existing GtChildProjects JSON string,
    # replacing any entry for the same SiteId.
    function Merge-ChildProjects {
        param([string] $ExistingJson)

        $projects = @()
        if (-not [string]::IsNullOrWhiteSpace($ExistingJson)) {
            try {
                $projects = @($ExistingJson | ConvertFrom-Json)
                Write-Output "Existing child projects found: $($projects.Count)"
            }
            catch {
                Write-Output "Could not parse existing GtChildProjects, starting with new array"
                $projects = @()
            }
        }

        $projects = @($projects | Where-Object { $_.SiteId -ne $currentSiteId })
        $projects = $projects + $childProjectObject
        return ConvertTo-Json @($projects) -Compress
    }

    Write-Output "Connecting to parent site: $parentSiteUrl"
    Connect-PnPOnline -Url $parentSiteUrl -ManagedIdentity

    $parentSite = Get-PnPSite -Includes Id
    $parentSiteId = $parentSite.Id.ToString()

    Write-Output "Getting first item from 'Prosjektegenskaper' list on parent site"
    $listItem = Get-PnPListItem -List "Prosjektegenskaper" -PageSize 1

    if ($null -ne $listItem -and $listItem.Count -gt 0) {
        $updatedChildProjectsJson = Merge-ChildProjects -ExistingJson $listItem["GtChildProjects"]
        Write-Output "Updating parent site 'Prosjektegenskaper' with: $updatedChildProjectsJson"

        Set-PnPListItem -List "Prosjektegenskaper" -Identity $listItem.Id -Values @{
            "GtChildProjects" = $updatedChildProjectsJson
        }

        Write-Output "Successfully updated parent site 'Prosjektegenskaper' list"
    }
    else {
        Write-Warning "No items found in 'Prosjektegenskaper' list on parent site"
    }

    if ([string]::IsNullOrWhiteSpace($hubSiteUrl)) {
        Write-Output "Hub site information not available, skipping hub site update"
        return
    }

    Write-Output "Connecting to hub site: $hubSiteUrl"
    Connect-PnPOnline -Url $hubSiteUrl -ManagedIdentity

    Write-Output "Searching for project in 'Prosjekter' list where GtSiteId equals parent site ID: $parentSiteId"

    $parentProjectItem = Get-PnPListItem -List "Prosjekter" -PageSize 5000 | Where-Object {
        $_.FieldValues["GtSiteId"] -eq $parentSiteId
    }

    if ($null -eq $parentProjectItem) {
        Write-Warning "Could not find parent project (GtSiteId: $parentSiteId) in hub site 'Prosjekter' list"
        return
    }

    Write-Output "Found parent project item in hub site 'Prosjekter' list (ID: $($parentProjectItem.Id))"

    $updatedHubChildProjectsJson = Merge-ChildProjects -ExistingJson $parentProjectItem["GtChildProjects"]
    Write-Output "Updating hub site 'Prosjekter' with: $updatedHubChildProjectsJson"

    Set-PnPListItem -List "Prosjekter" -Identity $parentProjectItem.Id -Values @{
        "GtChildProjects" = $updatedHubChildProjectsJson
    }

    Write-Output "Successfully updated hub site 'Prosjekter' list"
}

function DisableNoScript {
    # Tenant-admin cmdlet.
    Connect-Admin
    Write-Output "Disabling NoScript mode so all site customizations can be applied"
    Set-PnPTenantSite -Url $siteUrl -NoScriptSite:$false
    Write-Output "NoScript mode disabled"
}

function EnableNoScript {
    # Tenant-admin cmdlet, and earlier steps may have left the connection on a site.
    Connect-Admin
    Write-Output "Re-enabling NoScript mode after site configuration"
    Set-PnPTenantSite -Url $siteUrl -NoScriptSite:$true
    Write-Output "NoScript mode re-enabled"
}

# Per-step outcome table at the end of the job log. This is what you read first when a
# request comes back as "Space Creation Failed" - it shows which steps ran, which one
# broke, and what the underlying error was.
function Write-StepSummary {
    Write-Output ""
    Write-Output "================ Step summary ================"
    foreach ($result in $script:stepResults) {
        if ($result.Status -eq 'Succeeded') {
            Write-Output ("  {0,-28} {1}" -f $result.Step, $result.Status)
        }
        else {
            Write-Output ("  {0,-28} {1} - {2}" -f $result.Step, $result.Status, $result.Error)
        }
    }
    Write-Output "=============================================="
}

try {
    #Connect to spo
    Connect-Admin

    #Check connection
    if (-not (Get-PnPContext)) {
        throw "Issue connecting to SharePoint Online"
    }
    Write-Output "Connected to SharePoint Online"

    if ($spaceTypeInternal -eq "Viva Engage Community") {
        Write-Output "Site configuration not required"
    }
    else {
        # Container-level settings first. A sensitivity label overrides the site's
        # privacy, external sharing and unmanaged-device policy, so it has to be
        # applied before the settings it governs.
        Invoke-Step 'SetSensitivityLabel'
        Invoke-Step 'SetExternalSharing'

        # Disable NoScript so all site customizations (PnP template/custom packages,
        # features, property bag, etc.) can be applied. Restored in the finally block.
        Invoke-Step 'DisableNoScript'

        try {
            $configurationSteps = @(
                'AddOwners'
                'AddMembers'
                'AddVisitors'
                'AddReadOnlyGroup'
                'AddSiteCollectionAdmins'
                'SetAccessRequestSettings'
                'SetSiteLogo'
                'SetRegionalSettings'
                'ActivateFeatures'
                'ApplyPnPTemplate'
                'ApplyTheme'
                'DisableDocumentSync'
                'SetRetentionLabel'
                'SetSensitivityLabelLibrary'
                'SetSiteClassification'
                'SetMetadata'
                'JoinOrRegisterHubSite'
                'SetStorageQuota'
                'ApplySiteDesign'
                'UpdateParentSite'
            )

            foreach ($step in $configurationSteps) {
                Invoke-Step $step
            }
        }
        finally {
            # Always restore NoScript, even if a configuration step failed
            Invoke-Step 'EnableNoScript'
        }

        Write-StepSummary

        # Check if any errors occurred during configuration
        if ($script:hasErrors) {
            # This message becomes the Automation job's exception, which the logic app
            # reads back into StatusReason - so it has to name the failing steps.
            throw ("One or more configuration steps failed: " + ($script:errorMessages -join "; "))
        }

        Write-Output "Site configuration successful"
    }
}
catch {
    #Script error
    $errorMsg = "An error occured: $($PSItem.ToString())"

    # The step table has not been written yet if we failed outside the step loop.
    if ($script:stepResults.Count -gt 0 -and -not $script:hasErrors) {
        Write-StepSummary
    }

    Write-Error $errorMsg -ErrorAction Continue

    # Re-throw so the Automation job fails and the logic app can pick up the reason
    throw $errorMsg
}
