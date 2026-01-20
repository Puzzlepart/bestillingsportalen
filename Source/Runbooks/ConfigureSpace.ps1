#Runbook to configure collaboration spaces post provisioning - for use with the Bestillingsportalen solution
[CmdletBinding()] 
Param
(
    [Parameter (Mandatory = $false)]
    [String] $groupId,
    [String] $siteUrl,
    [String] $spaceType,
    [String] $spaceTypeInternal,
    [String] $externalSharing,
    [String] $owners,
    [String] $members,
    [String] $visitors,
    [String] $visibility,
    [String] $classification,
    [String] $joinHub,
    [String] $hubSiteId,
    [String] $timeZoneId,
    [String] $lcid,
    [bool] $enableAllowAccessRequests,
    [String] $defaultExternalSharingSetting,
    [Int] $storageQuota,
    [Int] $storageQuotaWarning,
    [bool] $syncHubPermissions,
    [bool] $disableDocSync,
    [String] $retentionLabel,
    [String] $sensitivityLabel,
    [String] $sensitivityLabelLibrary,
    [String] $featuresToActivate,
    [String] $applyPnPTemplate,
    [String] $pnpTemplateUrl,
    [String] $themeName,
    [String] $siteTemplateTitle,
    [String] $siteCollectionAdmins,
    [String] $siteDesignId,
    [string] $spaceImage,
    [bool] $internalChannel,
    [bool] $readOnlyGroup,
    [string] $defaultReadOnlyGroup
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

function SetSensitivityLabel {
    try {
        if ($sensitivityLabel -ne "") {
            try {
                Write-Output "Setting sensitivity label $sensitivityLabel on site"
                
                Set-PnPTenantSite -Identity $siteUrl -SensitivityLabel $sensitivityLabel
                
                Write-Output "Finished setting sensitivity label on site"
            }
            catch {
                Write-Output $_.Exception.Message
            }
        }
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

                $web.Features.Add($featureId, $force, [Microsoft.SharePoint.Client.FeatureDefinitionScope]::None)
                $ctx.ExecuteQuery()

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
                        throw
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

        if ($null -ne $metadata -and "" -ne $metadata) {
            try {
                $metadataObject = $metadata | ConvertFrom-Json
                Write-Output "Successfully parsed metadata JSON: $metadataObject"
            }
            catch {
                Write-Error "Failed to parse metadata JSON: $($_.Exception.Message)"
                return
            }

            # Handle propertyBagProps
            if ($null -ne $metadataObject.propertyBagProps) {
                Write-Output ""
                Write-Output "Processing propertyBagProps"
                Write-Output "***************************"
                try {
                    Write-Output "Disabling no script mode"
                    # Disable no script mode to allow property bag updates
                    Set-PnPTenantSite -Url $siteUrl -NoScriptSite:$false

                    foreach ($prop in $metadataObject.propertyBagProps) {
                        $propName = $prop.name
                        $propValue = $prop.value
                        if ($null -ne $propName -and $null -ne $propValue) {
                            try {
                                Write-Output "Adding property bag value for '$propName'"
                                Set-PnPPropertyBagValue -Key $propName -Value $propValue
                            }
                            catch {
                                Write-Output "Error adding property bag value for '$propName': $($_.Exception.Message)"
                            }
                        }
                    }

                    Write-output "Re-enabling no script mode"
                    # Enable no script mode to prevent property bag updates
                    Set-PnPTenantSite -Url $siteUrl -NoScriptSite:$true
                    Write-Output "Finished processing propertyBagProps"
                }
                catch {
                    Write-Output "Error processing propertyBagProps: $($_.Exception.Message)"
                }
            }

            Write-Output "Finished processing metadata"
        }
        else {
            Write-Warning "No metadata provided"
        }
    }
    catch {
        Set-SpaceCreationFailed -FunctionName "SetMetadata" -ErrorMessage $_.Exception.Message
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

            SetExternalSharing

            Connect-PnPOnline -Url $siteUrl -ManagedIdentity

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
            SetSensitivityLabel
            SetSensitivityLabelLibrary
            SetSiteClassification
            SetMetadata
            JoinOrRegisterHubSite
            SetStorageQuota
            ApplySiteDesign

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
    if (-not $script:hasErrors) {
        Update-ProvisioningRequestStatus -SiteUrl $siteUrl -Status "Space Creation Failed" -StatusReason $errorMsg
    }
    
    # Re-throw the error so Logic App can catch it
    throw
}
