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

$tenantName = $siteUrl.Substring(0, $siteUrl.IndexOf(".")).Replace("https://", "")

# Global variables for error tracking
$script:hasErrors = $false
$script:errorMessages = @()

# Function to handle errors and update the provisioning request status
function Set-SpaceCreationFailed {
    param(
        [string]$FunctionName,
        [string]$ErrorMessage
    )
    
    $script:hasErrors = $true
    $script:errorMessages += "$FunctionName failed: $ErrorMessage"
    
    Write-Error "[$FunctionName] $ErrorMessage"
}

# Function to update the provisioning request status to "Space Creation Failed"
function Update-ProvisioningRequestStatus {
    param(
        [string]$SiteUrl,
        [string]$Status,
        [string]$StatusReason
    )
    
    try {
        Write-Output "Updating provisioning request status to: $Status"
        Write-Output "Status reason: $StatusReason"
        
        # Note: The actual status update will be performed by the Logic App
        # This runbook will throw an error which the Logic App will catch
        # and handle via the error handling scopes
        
        # Log all accumulated errors
        if ($script:errorMessages.Count -gt 0) {
            Write-Output "Accumulated errors during space configuration:"
            foreach ($msg in $script:errorMessages) {
                Write-Output "  - $msg"
            }
        }
    }
    catch {
        Write-Error "Failed to log status update: $($_.Exception.Message)"
        throw $_
    }
}

function SetSiteLogo {
    try {
        if ($spaceImage -ne "") {
            Write-Output "Adding site logo (convert base64 to image)"
            $logoFileName = "$groupId.png"
            $logoPath = "$env:TEMP\$logoFileName"
            Write-Output  $logoFileName
            Write-Output  $logoPath

            $base64 = $spaceImage
            $bytes = [System.Convert]::FromBase64String($base64)
            [System.IO.File]::WriteAllBytes($logoPath, $bytes)
            
            Write-Output "Setting site logo"

            try {
                Set-PnPMicrosoft365Group -Identity $groupId -GroupLogoPath $logoPath
            }
            catch {
                Write-Output "Error setting site logo (Set-PnPMicrosoft365Group): $($_.Exception.Message)"
                throw $_
            }

            Write-Output "Adding logo to site assets library"

            $web = Get-PnPWeb
            $siteAssets = Get-PnPList -Identity "SiteAssets" -ErrorAction SilentlyContinue
            if ($null -eq $siteAssets) {
                $web.Lists.EnsureSiteAssetsLibrary()
                Invoke-PnPQuery -ErrorAction SilentlyContinue
            }

            $uploadedFile = Add-PnPFile -Path $logoPath -Folder "SiteAssets" -ErrorAction SilentlyContinue
            $siteAssetsLogoPath = "$($web.ServerRelativeUrl)/SiteAssets/$($logoFileName)"
            $webOutput = Set-PnPWebHeader -SiteLogoUrl $siteAssetsLogoPath -SiteThumbnailUrl $siteAssetsLogoPath -ErrorAction SilentlyContinue
            Write-Output "Finished setting site logo"
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "SetSiteLogo" -ErrorMessage $_.Exception.Message
    }
}

function AddOwners {
    try {
        If ($spaceTypeInternal -notin "Office 365 Group", "Project") {
            Write-Output "Updating SP owners group"
            $group = Get-PnPGroup -AssociatedOwnerGroup
            ForEach ($owner in $owners -split ",") {
                #Get the group
                Write-Output("Adding '$owner' to Owners")
                Add-PnPGroupMember -LoginName $owner -Identity $group
            }
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "AddOwners" -ErrorMessage $_.Exception.Message
    }
}

function AddMembers {
    try {
        Write-Output("Running 'AddMembers'")
        If ($members -ne "" -and $spaceTypeInternal -notin "Office 365 Group", "Project") {
            Write-Output "Updating SP members group"
            ForEach ($member in $members -split ",") {
                #Get the group
                $group = Get-PnPGroup -AssociatedMemberGroup
                Add-PnPGroupMember -LoginName $member -Identity $group
            }

            Write-Output "Finished updating SP members group"
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "AddMembers" -ErrorMessage $_.Exception.Message
    }
}

function AddVisitors {
    try {
        Write-Output("Running 'AddVisitors'")
        if ($visitors -ne "") {
            Write-Output "Updating SP visitors group"
            ForEach ($visitor in $visitors -split ",") {
                #Get the group
                $group = Get-PnPGroup -AssociatedVisitorGroup
                Add-PnPUserToGroup -LoginName $visitor -Identity $group
            }

            Write-Output "Finished updating SP visitors group"
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "AddVisitors" -ErrorMessage $_.Exception.Message
    }
}

function AddReadOnlyGroup {
    try {
        Write-Output("Running 'AddReadOnlyGroup'")
        if ($readOnlyGroup -and $defaultReadOnlyGroup -ne "") {
            try {
                Write-Output "Updating SP visitors group with read-only group"
                #Get the group
                $group = Get-PnPGroup -AssociatedVisitorGroup
                Add-PnPGroupMember -Group $group -LoginName $defaultReadOnlyGroup
                Write-Output "Finished updating SP visitors group"
            }
            catch {
                Write-Output "Error updating SP visitors group with read-only group: $($_.Exception.Message)"
                throw $_
            }
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "AddReadOnlyGroup" -ErrorMessage $_.Exception.Message
    }
}

function AddSiteCollectionAdmins {
    try {
        Write-Output("Running 'AddSiteCollectionAdmins'")
        If ($spaceTypeInternal -notin "Office 365 Group", "Project") {
            Write-Output "Adding Site Collection Administrators"
            ForEach ($sca in $siteCollectionAdmins -split ",") {
                #Add the sca
                Add-PnPSiteCollectionAdmin -Owners $sca
            }
            Write-Output "Finished adding Site Collection Administrators"
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "AddSiteCollectionAdmins" -ErrorMessage $_.Exception.Message
    }
}

function SetExternalSharing {
    try {
        Write-Output("Running 'SetExternalSharing'")
        if ($externalSharing) {

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
			
            }

            Write-Output "Finished configuring sharing settings"
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "SetExternalSharing" -ErrorMessage $_.Exception.Message
    }
}

function SetAccessRequestSettings {
    try {
        Write-Output("Running 'SetAccessRequestSettings'")
        #Disable access requests if visibility set to private
        If ($visibility -eq "Private" -and $enableAllowAccessRequests -eq $false) {
            Write-Output "Disabling access requests"
            $ctx = Get-PnPContext
            $ctx.Web.RequestAccessEmail = ""
            $ctx.ExecuteQuery()
            Write-Output "Finished disabling access requests"
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "SetAccessRequestSettings" -ErrorMessage $_.Exception.Message
    }
}

function SetSiteClassification {
    try {
        If ($spaceTypeInternal -notin "Office 365 Group", "Project") {
            Write-Output $classification
            If ($classification -ne "") {
                Write-Output "Setting classification"
                Set-PnPSite -Classification $classification
                Write-Output "Finished setting classification"
            }
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "SetSiteClassification" -ErrorMessage $_.Exception.Message
    }
}

function JoinOrRegisterHubSite {
    try {
        Write-Output "Checking if joining a hub site"
        #Join hub site if space type is not a hub
        if ($joinHub -eq $true -and $spaceTypeInternal -ne "Hub Site") {
            Write-Output "Joining hub site"
            Connect-PnPOnline -Url "https://$tenantName-admin.sharepoint.com" -ManagedIdentity

            #Get hub site url
            $hubSite = Get-PnPHubSite | Where-Object SiteId -eq $hubSiteId | Select-Object -Property SiteUrl
            Add-PnPHubSiteAssociation -Site $siteUrl -HubSite $hubSite.SiteUrl

            Write-Output "Finished joining hub site"
        }
        else {
            Write-Output "Checking if provisioning a hub site"
            #Register as a hub site
            if ($spaceTypeInternal -eq "Hub Site") {
        
                try {
                    Write-Output "Registering site as a hub"
                    Connect-PnPOnline -Url "https://$tenantName-admin.sharepoint.com" -ManagedIdentity
                    Register-PnPHubSite -Site $siteUrl
                    Write-Output "Finished registering site as a hub"

                    if ($syncHubPermissions) {
                        Write-Output "Enabling hub permissions sync"
                        Set-PnPHubSite -Identity $siteUrl -EnablePermissionsSync
                        Write-Output "Finished enabling hub permissions sync"
                    }
                }
                catch {
                    Write-Output $_.Exception.Message
                    throw $_
                }
            }
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "JoinOrRegisterHubSite" -ErrorMessage $_.Exception.Message
    }
}

function SetRegionalSettings {
    try {
        #Set regional settings for the site
        Write-Output "Setting regional settings"
        $web = Get-PnPWeb -Includes RegionalSettings, RegionalSettings.TimeZones
        $timeZone = $web.RegionalSettings.TimeZones | Where-Object { $_.Id -eq $timeZoneId }
        $web.RegionalSettings.LocaleId = $lcid
        $web.RegionalSettings.TimeZone = $timeZone
        $web.Update()
        Invoke-PnPQuery
        Write-Output "Finished setting regional settings"
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "SetRegionalSettings" -ErrorMessage $_.Exception.Message
    }
} 

function SetStorageQuota {
    try {
        If ($storageQuota -ne 0 -and $storageQuotaWarning -ne 0) {
            Write-Output "Setting site storage quota"

            Connect-PnPOnline -Url "https://$tenantName-admin.sharepoint.com" -ManagedIdentity
            Set-PnPTenantSite -Url $siteUrl -StorageMaximumLevel $storageQuota -StorageWarningLevel $storageQuotaWarning

            Write-Output "Finished setting storage quota"
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "SetStorageQuota" -ErrorMessage $_.Exception.Message
    }
}

function DisableDocumentSync {
    try {
        if ($disableDocSync) {
            Write-Output "Disabling sync option in 'Dokumenter' library"

            $list = Get-PnPList "Dokumenter"
 
            #Exclude List or Library from Sync
            $List.ExcludeFromOfflineClient = $true
            $List.Update()
            Invoke-PnPQuery

            Write-Output "Finished disabling sync option"
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "DisableDocumentSync" -ErrorMessage $_.Exception.Message
    }
}

function SetRetentionLabel {
    try {
        if ($retentionLabel -ne "") {
            Write-Output "Setting retention label $retentionLabel on 'Dokumenter' library"

            $list = Get-PnPList "Dokumenter"

            Set-PnPLabel -List $list -Label $retentionLabel

            Write-Output "Finished setting retention label"
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "SetRetentionLabel" -ErrorMessage $_.Exception.Message
    }
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
    try {
        if ($sensitivityLabel -eq "") { return }

        # Respect the admin kill-switch even if a request carries a label id anyway
        # (hand-edited list item, stale front-end).
        if ($enableSensitivityLabels -ne "" -and $enableSensitivityLabels -inotin @("true", "1")) {
            Write-Output "Sensitivity labels are disabled (EnableSensitivityLabels = '$enableSensitivityLabels') - skipping label $sensitivityLabel"
            return
        }

        Write-Output "Setting sensitivity label $sensitivityLabel (app-only attempt)"
        try {
            Set-PnPTenantSite -Identity $siteUrl -SensitivityLabel $sensitivityLabel
            Write-Output "Set-PnPTenantSite returned without error"
        }
        catch {
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
    catch {
        Set-SpaceCreationFailed -FunctionName "SetSensitivityLabel" -ErrorMessage $_.Exception.Message
    }
}

function SetSensitivityLabelLibrary {
    try {
        if ($sensitivityLabelLibrary -ne "") {
            try {
                Write-Output "Setting sensitivity label $sensitivityLabelLibrary on 'Dokumenter' library"

                $list = Get-PnPList "Dokumenter"
                
                Set-PnPList -Identity $list -DefaultSensitivityLabelForLibrary $sensitivityLabelLibrary

                Write-Output "Finished setting sensitivity label"
            }
            catch {
                Write-Output $_.Exception.Message
                throw $_
            }
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "SetSensitivityLabelLibrary" -ErrorMessage $_.Exception.Message
    }
}

function ActivateFeatures {
    try {
        If ($featuresToActivate -ne "") {
            try {
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

                    $featureId = "41e1d4bf-b1a2-47f7-ab80-d5d6cbba3092"

                    try {
                        Write-Output "Pre-activating push notifications feature"
                        $web.Features.Add($featureId, $force, [Microsoft.SharePoint.Client.FeatureDefinitionScope]::None)
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
            catch {
                Write-Output $_.Exception.Message
                throw $_
            }
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "ActivateFeatures" -ErrorMessage $_.Exception.Message
    }
}

function ApplyPnPTemplate {
    try {
        if ($applyPnPTemplate -eq $true) {
            Write-Output "Applying PnP template"

            $maxRetries = 3
            $retryCount = 0
            $success = $false

            while ($retryCount -lt $maxRetries -and -not $success) {
                try {
                    $retryCount++
                    Write-Output "Attempt $retryCount of $maxRetries to apply PnP template"

                    #Apply the template
                    Invoke-PnPSiteTemplate -Path $pnpTemplateUrl -ClearNavigation

                    $success = $true
                    Write-Output "Finished applying PnP template"
                }
                catch {
                    Write-Output "Error applying PnP template (Attempt $retryCount): $($_.Exception.Message)"

                    if ($retryCount -lt $maxRetries) {
                        $waitTime = 10 * $retryCount
                        Write-Output "Waiting $waitTime seconds before retry..."
                        Start-Sleep -Seconds $waitTime
                    }
                    else {
                        Write-Error "Failed to apply PnP template after $maxRetries attempts: $($_.Exception.Message)"
                        throw $_
                    }
                }
            }
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "ApplyPnPTemplate" -ErrorMessage $_.Exception.Message
    }
}

function ApplyTheme {
    try {
        if ($themeName -ne "") {
            Write-Output "Applying $themeName theme"

            #Apply the theme
            Set-PnPWebTheme -Theme $themeName

            Write-Output "Finished applying theme"
		
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "ApplyTheme" -ErrorMessage $_.Exception.Message
    }
}

function ApplySiteDesign {
    try {
        # Reapply site design if we have applied a PnP template
        if ($applyPnPTemplate -eq $true -and $siteDesignId -ne $null -and $siteDesignId -ne "") {
            Write-Output "Applying site design"

            Connect-PnPOnline -Url "https://$tenantName-admin.sharepoint.com" -ManagedIdentity
            Invoke-PnPSiteDesign -Identity $siteDesignId -WebUrl $siteUrl

            Write-Output "Finished applying site design"
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "ApplySiteDesign" -ErrorMessage $_.Exception.Message
    }
}

function SetMetadata {
    try {
        Write-Output "Running 'SetMetadata'"

        if ($null -ne $metadata -and $metadata -ne "") {
            # Convert metadata to string if it's not already
            if ($metadata -is [string]) {
                $metadataString = $metadata
            }
            else {
                $metadataString = $metadata | ConvertTo-Json -Compress -Depth 10
            }
            
            try {
                $metadataObject = $metadataString | ConvertFrom-Json
                Write-Output "Successfully parsed metadata JSON"
            }
            catch {
                Write-Error "Failed to parse metadata JSON: $($_.Exception.Message)"
                throw $_
            }

            # Handle propertyBagProps
            if ($null -ne $metadataObject.propertyBagProps) {
                Write-Output ""
                Write-Output "Processing propertyBagProps"
                Write-Output "***************************"
                try {
                    # NoScript is already disabled for the whole configuration run (see DisableNoScript/EnableNoScript)
                    foreach ($prop in $metadataObject.propertyBagProps) {
                        $propName = $prop.name
                        $propValue = $prop.value
                        if ($null -ne $propName -and $null -ne $propValue) {
                            try {
                                Write-Output "Adding property bag value for '$propName'"
                                
                                if ($prop.indexed -eq $true) {
                                    Write-Output "Setting property '$propName' as indexed"
                                    Set-PnPPropertyBagValue -Key $propName -Value $propValue -Indexed
                                }
                                else {
                                    Set-PnPPropertyBagValue -Key $propName -Value $propValue
                                }
                            }
                            catch {
                                Write-Output "Error adding property bag value for '$propName': $($_.Exception.Message)"
                                throw $_
                            }
                        }
                    }

                    Write-Output "Finished processing propertyBagProps"
                }
                catch {
                    Write-Output "Error processing propertyBagProps: $($_.Exception.Message)"
                    throw $_
                }
            }

            Write-Output "Finished processing metadata"
        }
        else {
            Write-Output "No metadata provided"
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "SetMetadata" -ErrorMessage $_.Exception.Message
    }
}

function UpdateParentSite {
    try {
        Write-Output "Running 'UpdateParentSite'"

        if ($null -ne $parentSiteUrl -and "" -ne $parentSiteUrl) {
            Write-Output "Parent site specified: $parentSiteUrl" 

            Connect-PnPOnline -Url $siteUrl -ManagedIdentity
            $currentSite = Get-PnPSite -Includes Id, Url
            $currentWeb = Get-PnPWeb
            $currentSiteId = $currentSite.Id.ToString()
            $currentSiteTitle = $currentWeb.Title
            $currentSiteUrl = $currentSite.Url

            $hubSiteInfo = $null
            $hubSiteUrl = ""
            $hubSiteTitle = ""
            
            if ($null -ne $hubSiteId -and "" -ne $hubSiteId) {
                try {
                    Connect-PnPOnline -Url "https://$tenantName-admin.sharepoint.com" -ManagedIdentity
                    $hubSiteInfo = Get-PnPHubSite -Identity $hubSiteId -ErrorAction SilentlyContinue
                    
                    if ($null -ne $hubSiteInfo) {
                        $hubSiteUrl = $hubSiteInfo.SiteUrl
                        $hubSiteTitle = $hubSiteInfo.Title
                        Write-Output "Hub site information retrieved: $hubSiteTitle ($hubSiteUrl)"
                    }
                }
                catch {
                    Write-Output "Could not retrieve hub site information: $($_.Exception.Message)"
                    throw $_
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

            $childProjectJson = ConvertTo-Json @($childProjectObject) -Compress

            Write-Output "Child project data: $childProjectJson"

            try {
                Write-Output "Connecting to parent site: $parentSiteUrl"
                Connect-PnPOnline -Url $parentSiteUrl -ManagedIdentity

                $parentSite = Get-PnPSite -Includes Id
                $parentSiteId = $parentSite.Id.ToString()

                Write-Output "Getting first item from 'Prosjektegenskaper' list on parent site"
                $listItem = Get-PnPListItem -List "Prosjektegenskaper" -PageSize 1
                
                if ($null -ne $listItem -and $listItem.Count -gt 0) {
                    
                    $existingChildProjects = $listItem["GtChildProjects"]
                    $childProjectsArray = @()

                    if ($null -ne $existingChildProjects -and "" -ne $existingChildProjects) {
                        try {
                            $childProjectsArray = @($existingChildProjects | ConvertFrom-Json)
                            Write-Output "Existing child projects found: $($childProjectsArray.Count)"
                        }
                        catch {
                            Write-Output "Could not parse existing GtChildProjects, starting with new array"
                            $childProjectsArray = @()
                        }
                    }

                    # Add new child project if not already present
                    $existingProject = $childProjectsArray | Where-Object { $_.SiteId -eq $currentSiteId }
                    if ($null -eq $existingProject) {
                        $childProjectsArray = $childProjectsArray + $childProjectObject
                        Write-Output "Added new child project to array"
                    }
                    else {
                        Write-Output "Child project already exists in parent site, updating entry"
                        $childProjectsArray = @($childProjectsArray | Where-Object { $_.SiteId -ne $currentSiteId })
                        $childProjectsArray = $childProjectsArray + $childProjectObject
                    }

                    $updatedChildProjectsJson = ConvertTo-Json @($childProjectsArray) -Compress
                    Write-Output "Updating parent site 'Prosjektegenskaper' with: $updatedChildProjectsJson"
                    
                    Set-PnPListItem -List "Prosjektegenskaper" -Identity $listItem.Id -Values @{
                        "GtChildProjects" = $updatedChildProjectsJson
                    }
                    
                    Write-Output "Successfully updated parent site 'Prosjektegenskaper' list"
                }
                else {
                    Write-Warning "No items found in 'Prosjektegenskaper' list on parent site"
                }
            }
            catch {
                Write-Output "Error updating parent site: $($_.Exception.Message)"
                throw $_
            }

            if ($null -ne $hubSiteUrl -and "" -ne $hubSiteUrl) {
                try {
                    Write-Output "Connecting to hub site: $hubSiteUrl"
                    Connect-PnPOnline -Url $hubSiteUrl -ManagedIdentity

                    Write-Output "Searching for project in 'Prosjekter' list where GtSiteId equals parent site ID: $parentSiteId"
                    
                    $prosjekterItems = Get-PnPListItem -List "Prosjekter" -PageSize 5000
                    
                    $parentProjectItem = $prosjekterItems | Where-Object { 
                        $_.FieldValues["GtSiteId"] -eq $parentSiteId 
                    }

                    if ($null -ne $parentProjectItem) {
                        Write-Output "Found parent project item in hub site 'Prosjekter' list (ID: $($parentProjectItem.Id))"
                        
                        $existingHubChildProjects = $parentProjectItem["GtChildProjects"]
                        $hubChildProjectsArray = @()

                        if ($null -ne $existingHubChildProjects -and "" -ne $existingHubChildProjects) {
                            try {
                                $hubChildProjectsArray = @($existingHubChildProjects | ConvertFrom-Json)
                                Write-Output "Existing child projects found in hub site: $($hubChildProjectsArray.Count)"
                            }
                            catch {
                                Write-Output "Could not parse existing GtChildProjects in hub site, starting with new array"
                                $hubChildProjectsArray = @()
                            }
                        }

                        $existingHubProject = $hubChildProjectsArray | Where-Object { $_.SiteId -eq $currentSiteId }
                        if ($null -eq $existingHubProject) {
                            $hubChildProjectsArray = $hubChildProjectsArray + $childProjectObject
                            Write-Output "Added new child project to hub site array"
                        }
                        else {
                            Write-Output "Child project already exists in hub site, updating entry"
                            $hubChildProjectsArray = @($hubChildProjectsArray | Where-Object { $_.SiteId -ne $currentSiteId })
                            $hubChildProjectsArray = $hubChildProjectsArray + $childProjectObject
                        }

                        $updatedHubChildProjectsJson = ConvertTo-Json @($hubChildProjectsArray) -Compress
                        Write-Output "Updating hub site 'Prosjekter' with: $updatedHubChildProjectsJson"
                        
                        Set-PnPListItem -List "Prosjekter" -Identity $parentProjectItem.Id -Values @{
                            "GtChildProjects" = $updatedHubChildProjectsJson
                        }
                        
                        Write-Output "Successfully updated hub site 'Prosjekter' list"
                    }
                    else {
                        Write-Warning "Could not find parent project (GtSiteId: $parentSiteId) in hub site 'Prosjekter' list"
                    }
                }
                catch {
                    Write-Output "Error updating hub site 'Prosjekter' list: $($_.Exception.Message)"
                    throw $_
                }
            }
            else {
                Write-Output "Hub site information not available, skipping hub site update"
            }

            Connect-PnPOnline -Url $siteUrl -ManagedIdentity

            Write-Output "Finished updating parent site and hub site"
        }
        else {
            Write-Output "No parent site specified, skipping UpdateParentSite"
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "UpdateParentSite" -ErrorMessage $_.Exception.Message
    }
}

function DisableNoScript {
    try {
        Write-Output "Disabling NoScript mode so all site customizations can be applied"
        Set-PnPTenantSite -Url $siteUrl -NoScriptSite:$false
        Write-Output "NoScript mode disabled"
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "DisableNoScript" -ErrorMessage $_.Exception.Message
    }
}

function EnableNoScript {
    try {
        Write-Output "Re-enabling NoScript mode after site configuration"
        # Reconnect to the site context before toggling - earlier steps may have switched the connection
        Connect-PnPOnline -Url $siteUrl -ManagedIdentity
        Set-PnPTenantSite -Url $siteUrl -NoScriptSite:$true
        Write-Output "NoScript mode re-enabled"
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "EnableNoScript" -ErrorMessage $_.Exception.Message
    }
}

try {
    #Connect to spo
    Connect-PnPOnline -Url "https://$tenantName-admin.sharepoint.com" -ManagedIdentity

    #Check connection
    $context = Get-PnPContext
    if ($context) {
        Write-Output "Connected to SharePoint Online"

        if ($spaceTypeInternal -ne "Viva Engage Community") {

            # The container label governs privacy, external sharing and unmanaged-device
            # policy, and overrides whatever we set afterwards - so it goes first, while
            # we still hold the tenant admin connection.
            SetSensitivityLabel

            SetExternalSharing

            Connect-PnPOnline -Url $siteUrl -ManagedIdentity

            # Disable NoScript so all site customizations (PnP template/custom packages,
            # features, property bag, etc.) can be applied. Restored in the finally block.
            DisableNoScript

            try {
                AddOwners
                AddMembers
                AddVisitors
                AddReadOnlyGroup
                AddSiteCollectionAdmins
                SetAccessRequestSettings
                SetSiteLogo
                SetRegionalSettings
                ActivateFeatures
                ApplyPnPTemplate
                ApplyTheme
                DisableDocumentSync
                SetRetentionLabel
                SetSensitivityLabelLibrary
                SetSiteClassification
                SetMetadata
                JoinOrRegisterHubSite
                SetStorageQuota
                ApplySiteDesign
                UpdateParentSite
            }
            finally {
                # Always restore NoScript, even if a configuration step failed
                EnableNoScript
            }

            # Check if any errors occurred during configuration
            if ($script:hasErrors) {
                $combinedErrorMessage = "One or more configuration steps failed: " + ($script:errorMessages -join "; ")
                Update-ProvisioningRequestStatus -SiteUrl $siteUrl -Status "Space Creation Failed" -StatusReason $combinedErrorMessage
                throw $combinedErrorMessage
            }
            else {
                Write-Output "Site configuration successful"
            }

        }
        else {
            Write-Output "Site configuration not required"
        }
    
    }
    else {
        $errorMsg = "Issue connecting to SharePoint Online"
        Write-Error $errorMsg
        Update-ProvisioningRequestStatus -SiteUrl $siteUrl -Status "Space Creation Failed" -StatusReason $errorMsg
        throw $errorMsg
    }
}
catch {
    #Script error
    $errorMsg = "An error occured: $($PSItem.ToString())"
    Write-Error $errorMsg
    
    # Update status if not already updated
    if ($script:hasErrors) {
        Update-ProvisioningRequestStatus -SiteUrl $siteUrl -Status "Space Creation Failed" -StatusReason $errorMsg
    }
    
    # Re-throw the error so Logic App can catch it
    throw $errorMsg
}
