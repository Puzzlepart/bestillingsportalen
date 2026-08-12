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
    # Mirrors the EnableSensitivityLabels item in the 'Provisioning Request Settings'
    # list and is the admin kill-switch for the feature. Passed as a string because the
    # logic app interpolates its boolean variable.
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
$script:currentStepSkipReason = $null

# Connect helpers. Each step connects to the context it needs rather than relying on
# whatever the previous step happened to leave behind - tenant-admin cmdlets such as
# Set-PnPTenantSite used to be called while the connection pointed at the site itself.
#
# Connections are warmed up with retry: PnP acquires the token LAZILY on the first
# request after Connect-PnPOnline, and the Automation sandbox's identity endpoint has
# been seen returning an empty/unparsable response under quick successive token
# requests (every step reconnects) - PnP then fails the STEP with '[Managed Identity]
# The error response was either empty or could not be parsed'. Forcing the token
# acquisition here, inside a retry loop, keeps that transient out of the step results.
function Connect-WithRetry {
    param([Parameter(Mandatory = $true)][string] $Url)

    $maxAttempts = 4
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            Connect-PnPOnline -Url $Url -ManagedIdentity
            $null = Get-PnPWeb # forces the token acquisition now, inside the retry
            return
        }
        catch {
            if ($attempt -eq $maxAttempts) { throw }
            Write-Output "Connection warm-up for $Url failed (attempt $attempt/$maxAttempts): $($_.Exception.Message) - retrying in $(10 * $attempt)s"
            Start-Sleep -Seconds (10 * $attempt)
        }
    }
}

function Connect-Admin {
    Connect-WithRetry -Url $adminUrl
}

function Connect-Site {
    Connect-WithRetry -Url $siteUrl
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

# Called by a step that is not applicable to this request, right before it returns.
# Without this the step summary reports 'Succeeded' for steps that did nothing, which is
# technically true and useless when you are trying to work out why a theme was never
# applied. Most requests exercise fewer than half the steps, so "did the work" and
# "did not apply" have to be distinguishable.
function Skip-Step {
    param([Parameter(Mandatory = $true)][string] $Reason)

    $script:currentStepSkipReason = $Reason
    Write-Output "Skipped: $Reason"
}

# Runs one configuration step. A failing step is recorded and the run continues, so a
# bad theme name does not stop the retention label from being applied. The collected
# results are also what the caller reads back as the run's outcome.
function Invoke-Step {
    param([Parameter(Mandatory = $true)][string] $Name)

    Write-Output ""
    Write-Output "--- $Name ---"
    $script:currentStepSkipReason = $null

    try {
        & $Name

        if ($null -ne $script:currentStepSkipReason) {
            $script:stepResults += [pscustomobject]@{ Step = $Name; Status = 'Skipped'; Detail = $script:currentStepSkipReason }
        }
        else {
            $script:stepResults += [pscustomobject]@{ Step = $Name; Status = 'Succeeded'; Detail = $null }
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName $Name -ErrorMessage $_.Exception.Message
        $script:stepResults += [pscustomobject]@{ Step = $Name; Status = 'Failed'; Detail = $_.Exception.Message }
    }
}

# The name of the default document library varies with the site's language - the old
# hardcoded "Dokumenter" failed on every non-Norwegian site.
#
# Three strategies, most to least precise. IsDefaultDocumentLibrary is a CSOM property
# that Get-PnPList does not necessarily retrieve, and reading an unretrieved CSOM
# property throws PropertyOrFieldNotInitializedException - which under
# $ErrorActionPreference = 'Stop' would kill the step before any fallback ran. Hence the
# try/catch around the first attempt rather than a plain filter.
function Get-DefaultDocumentLibrary {
    $documentLibraries = @(Get-PnPList | Where-Object { $_.BaseTemplate -eq 101 -and -not $_.Hidden })

    # 1. The property, if this PnP version populated it.
    try {
        $library = $documentLibraries | Where-Object { $_.IsDefaultDocumentLibrary } | Select-Object -First 1
        if ($null -ne $library) {
            Write-Output "Default document library: '$($library.Title)' (IsDefaultDocumentLibrary)"
            return $library
        }
    }
    catch {
        Write-Output "IsDefaultDocumentLibrary was not available on this connection - falling back to name matching."
    }

    # 2. The well-known default titles, per site language.
    foreach ($candidate in @('Dokumenter', 'Shared Documents', 'Documents')) {
        $library = $documentLibraries | Where-Object { $_.Title -eq $candidate } | Select-Object -First 1
        if ($null -ne $library) {
            Write-Output "Default document library: '$($library.Title)' (matched a known default title)"
            return $library
        }
    }

    # 3. A single document library on the site can only be the default one.
    if ($documentLibraries.Count -eq 1) {
        Write-Output "Default document library: '$($documentLibraries[0].Title)' (only document library on the site)"
        return $documentLibraries[0]
    }

    throw ("Could not identify the default document library on $siteUrl. Found $($documentLibraries.Count) document libraries: " +
        (($documentLibraries | ForEach-Object { "'$($_.Title)'" }) -join ', ') +
        ". Add the site's default library title to Get-DefaultDocumentLibrary in ConfigureSpace.ps1.")
}

# Update-ProvisioningRequestStatus used to live here. It never updated anything - it
# only logged, because the actual list update belongs to the logic app. Write-StepSummary
# plus the thrown exception message now serve that purpose without the misleading name.

function SetSiteLogo {
    if ($spaceImage -eq "") {
        Skip-Step "No space image on the request"
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
    # Group-backed space types get their owners from the M365 group, not the SP group.
    if ($spaceTypeInternal -in "Office 365 Group", "Project") {
        Skip-Step "Space type '$spaceTypeInternal' takes owners from the M365 group, not the SP owners group"
        return
    }
    if ($owners -eq "") {
        Skip-Step "No owners on the request"
        return
    }

    Connect-Site
    Write-Output "Updating SP owners group"
    $group = Get-PnPGroup -AssociatedOwnerGroup
    ForEach ($owner in $owners -split ",") {
        Write-Output("Adding '$owner' to Owners")
        Add-PnPGroupMember -LoginName $owner -Identity $group
    }
}

function AddMembers {
    if ($spaceTypeInternal -in "Office 365 Group", "Project") {
        Skip-Step "Space type '$spaceTypeInternal' takes members from the M365 group, not the SP members group"
        return
    }
    if ($members -eq "") {
        Skip-Step "No members on the request"
        return
    }

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
    if ($visitors -eq "") {
        Skip-Step "No visitors on the request"
        return
    }

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
    if (-not $readOnlyGroup) {
        Skip-Step "Read-only group not requested"
        return
    }
    if ($defaultReadOnlyGroup -eq "") {
        Skip-Step "Read-only group requested, but DefaultReadOnlyGroup is not set in the settings list"
        return
    }

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
    if ($spaceTypeInternal -in "Office 365 Group", "Project") {
        Skip-Step "Space type '$spaceTypeInternal' takes its administrators from the M365 group owners"
        return
    }
    if ([string]::IsNullOrWhiteSpace($siteCollectionAdmins)) {
        Skip-Step "No site collection administrators supplied (the logic app does not currently send this parameter)"
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
        Skip-Step "External sharing not requested (ExternalSharingRequired = '$externalSharing')"
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
    if (-not ($visibility -eq "Private" -and $enableAllowAccessRequests -eq $false)) {
        Skip-Step "Access requests are only disabled for private spaces with EnableAllowAccessRequests = false (visibility '$visibility')"
        return
    }

    Connect-Site
    Write-Output "Disabling access requests"
    $ctx = Get-PnPContext
    $ctx.Web.RequestAccessEmail = ""
    $ctx.ExecuteQuery()
    Write-Output "Finished disabling access requests"
}

function SetSiteClassification {
    if ($spaceTypeInternal -in "Office 365 Group", "Project") {
        Skip-Step "Space type '$spaceTypeInternal' carries its classification on the M365 group"
        return
    }
    if ($classification -eq "") {
        Skip-Step "No classification on the request"
        return
    }

    Connect-Site
    Write-Output "Setting classification '$classification'"
    Set-PnPSite -Classification $classification
    Write-Output "Finished setting classification"
}

function JoinOrRegisterHubSite {
    # JoinHub comes from the provisioning type, the hub site id from the user's
    # selection in the web part. When the type says join but no hub was selected
    # (typically because the Hub Sites list is empty - GetHubSites never run, or no
    # hub has Enabled = true), the id arrives empty. That is a configuration gap, not
    # a provisioning failure - skip loudly instead of failing the whole request with
    # "Hub site with id '' was not found".
    if ($joinHubEnabled -and $spaceTypeInternal -ne "Hub Site" -and [string]::IsNullOrWhiteSpace($hubSiteId)) {
        Skip-Step "JoinHub is enabled for this provisioning type, but the request carries no hub site id. Run the GetHubSites logic app and set Enabled = true on a hub in the Hub Sites list (guide steps 7-8), or remove JoinHub from the provisioning type."
        return
    }

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

    Skip-Step "Not joining a hub (JoinHub = '$joinHub') and this is not a hub site itself"
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
    if ($storageQuota -eq 0 -or $storageQuotaWarning -eq 0) {
        Skip-Step "No storage quota configured (StorageQuota=$storageQuota, StorageQuotaWarning=$storageQuotaWarning)"
        return
    }

    Connect-Admin
    Write-Output "Setting site storage quota"
    Set-PnPTenantSite -Url $siteUrl -StorageMaximumLevel $storageQuota -StorageWarningLevel $storageQuotaWarning
    Write-Output "Finished setting storage quota"
}

function DisableDocumentSync {
    if (-not $disableDocSync) {
        Skip-Step "DisableDocumentSync not requested"
        return
    }

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
    if ($retentionLabel -eq "") {
        Skip-Step "No retention label on the request"
        return
    }

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

# Applies the Purview container label. Runs before the settings the label governs
# (privacy, external sharing, unmanaged devices), because the label overrides them.
#
# Requires the tenant admin connection - Set-PnPTenantSite is a tenant-admin cmdlet.
function SetSensitivityLabel {
    if ($sensitivityLabel -eq "") {
        Skip-Step "No sensitivity label on the request"
        return
    }

    # Respect the admin kill-switch even if a request carries a label id anyway
    # (hand-edited list item, stale front-end).
    if ($enableSensitivityLabels -ne "" -and $enableSensitivityLabels -inotin @("true", "1")) {
        Skip-Step "Request carries label $sensitivityLabel, but EnableSensitivityLabels is '$enableSensitivityLabels' in the settings list"
        return
    }

    Connect-Admin

    Write-Output "Setting sensitivity label $sensitivityLabel"
    Set-PnPTenantSite -Identity $siteUrl -SensitivityLabel $sensitivityLabel

    if ([string]::IsNullOrWhiteSpace($groupId)) {
        # No group behind the site, so the label lives on the site alone - nothing to
        # verify against a group.
        Write-Output "Site is not group-connected - finished setting sensitivity label"
        return
    }

    # Set-PnPTenantSite has been observed to report success without the label being
    # applied (pnp/powershell#4917), so no exception is not proof. Read it back off the
    # group - that is where the label actually governs privacy and guest sharing.
    if (-not (Test-GroupLabelApplied -GroupId $groupId -LabelId $sensitivityLabel)) {
        throw ("Sensitivity label $sensitivityLabel was set on the site but never appeared on group $groupId. " +
            "Check that the label is published to groups and sites in Purview (a label scoped only to files/email cannot be applied here), " +
            "that it is not still within the 24 hours after publishing, and that the label id matches an entry in the 'IP Labels' list. See Sensitivity-labels.md.")
    }

    Write-Output "Label confirmed on group $groupId - finished setting sensitivity label"
}

function SetSensitivityLabelLibrary {
    if ($sensitivityLabelLibrary -eq "") {
        Skip-Step "No library sensitivity label on the request"
        return
    }

    Connect-Site
    $list = Get-DefaultDocumentLibrary
    Write-Output "Setting sensitivity label $sensitivityLabelLibrary on '$($list.Title)' library"

    Set-PnPList -Identity $list -DefaultSensitivityLabelForLibrary $sensitivityLabelLibrary

    Write-Output "Finished setting sensitivity label on the library"
}

function ActivateFeatures {
    if ($featuresToActivate -eq "") {
        Skip-Step "No features to activate configured for this provisioning type"
        return
    }

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
    if (-not $applyPnPTemplateEnabled) {
        Skip-Step "ApplyPnPTemplate not requested (value '$applyPnPTemplate')"
        return
    }

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
    if ($themeName -eq "") {
        Skip-Step "No theme configured for this provisioning type"
        return
    }

    Connect-Site
    Write-Output "Applying $themeName theme"
    Set-PnPWebTheme -Theme $themeName
    Write-Output "Finished applying theme"
}

function ApplySiteDesign {
    # Reapply site design if we have applied a PnP template
    if (-not $applyPnPTemplateEnabled) {
        Skip-Step "Site design is only re-applied after a PnP template, which was not requested"
        return
    }
    if ([string]::IsNullOrWhiteSpace($siteDesignId)) {
        Skip-Step "No site design id on the request"
        return
    }

    Connect-Admin
    Write-Output "Applying site design $siteDesignId"
    Invoke-PnPSiteDesign -Identity $siteDesignId -WebUrl $siteUrl
    Write-Output "Finished applying site design"
}

function SetMetadata {
    if ($null -eq $metadata -or $metadata -eq "") {
        Skip-Step "No metadata on the request"
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

    # Handle propertyBagProps - the only metadata this runbook consumes
    if ($null -eq $metadataObject.propertyBagProps) {
        Skip-Step "Metadata was supplied but contained no propertyBagProps"
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
        Skip-Step "No parent site on the request"
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
# request comes back as "Space Creation Failed" - it shows which steps did work, which
# ones did not apply and why, and which one broke.
#
# The Skipped/Succeeded distinction matters: a typical request exercises fewer than half
# the steps, so a table of nothing but "Succeeded" cannot answer "why was my theme never
# applied?".
function Write-StepSummary {
    $done = @($script:stepResults | Where-Object { $_.Status -eq 'Succeeded' }).Count
    $skipped = @($script:stepResults | Where-Object { $_.Status -eq 'Skipped' }).Count
    $failed = @($script:stepResults | Where-Object { $_.Status -eq 'Failed' }).Count

    Write-Output ""
    Write-Output "===================== Step summary ====================="
    foreach ($result in $script:stepResults) {
        if ([string]::IsNullOrEmpty($result.Detail)) {
            Write-Output ("  {0,-9} {1}" -f $result.Status, $result.Step)
        }
        else {
            Write-Output ("  {0,-9} {1,-28} {2}" -f $result.Status, $result.Step, $result.Detail)
        }
    }
    Write-Output "--------------------------------------------------------"
    Write-Output ("  $done applied, $skipped not applicable, $failed failed")
    Write-Output "========================================================"
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
