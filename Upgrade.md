# Upgrading Bestillingsportalen

This guide explains how to upgrade an existing Bestillingsportalen installation to get the latest features and bug fixes without recreating your entire environment or losing your existing data.

## Overview

The upgrade process allows you to:
- Apply the latest PnP template updates (field definitions, content types, views, etc.)
- Update the ProcessProvisionRequest Logic App with the latest workflow improvements
- Preserve all existing list data (provisioning types, settings, requests, etc.)
- Minimize downtime and configuration changes

## When to Use Upgrade Mode

Use upgrade mode when you want to:
- Update an existing Bestillingsportalen installation to a newer version
- Apply template changes without resetting list data
- Update the core provisioning Logic App workflow
- Get new features or bug fixes without a full redeployment

**Do NOT use upgrade mode for:**
- Initial installation (use the standard deployment process)
- Major breaking changes that require data migration
- Complete environment rebuilds

## What Gets Updated

### ✅ Updated in Upgrade Mode

1. **PnP Template Application**
   - Site columns and content types
   - List schemas and field definitions
   - Views and forms
   - Navigation structure
   - Web parts and page layouts

2. **ProcessProvisionRequest Logic App**
   - Complete workflow replacement with latest version
   - Updated error handling
   - New provisioning features
   - Bug fixes and improvements

### ❌ NOT Updated in Upgrade Mode

1. **List Data** - All existing items are preserved:
   - Provisioning Request Settings
   - Provisioning Types (custom types you've added)
   - Site Templates
   - Hub Sites
   - Teams Templates
   - Time Zones
   - Locales
   - IP Labels
   - Existing provisioning requests

2. **Assets (Images/Icons)**:
   - Provisioning Type images
   - Provisioning Type icons
   - Other uploaded files

3. **Other Azure Resources**:
   - Azure Automation Account
   - Runbooks
   - Key Vault
   - Certificates
   - Other Logic Apps (GetSiteTemplates, GetHubSites, etc.)
   - API Connections

4. **Entra ID App**:
   - Application registration
   - App secrets
   - Permissions

## Prerequisites

Before starting the upgrade:

1. **Backup Your Environment**
   - Export critical list data (especially custom Provisioning Types)
   - Document any customizations you've made
   - Take screenshots of important configurations

2. **Review Release Notes**
   - Check what's new in the version you're upgrading to
   - Review any breaking changes or migration steps
   - Understand new features being added

3. **Verify Permissions**
   - Same permissions as initial deployment
   - Site Collection Administrator on the Bestillingsportalen site
   - Azure Contributor role on the resource group
   - Application Administrator or similar for Entra ID

4. **Have Your Parameters Ready**
   - Use the same `parameters.json` file from your initial deployment
   - Verify all values are still current

## Upgrade Process

### Step 1: Prepare Your Environment

1. Navigate to the Source/Scripts directory:
   ```bash
   cd Source/Scripts
   ```

2. Ensure your `parameters.json` file is up to date with your current environment settings.

3. Review the latest changes in the repository to understand what will be updated.

### Step 2: Run the Upgrade Deployment

#### Option A: Automatic Upgrade (Recommended)

Execute the deployment script with the `-Upgrade` flag:

```powershell
./deploy.ps1 -Upgrade
```

You can combine with other skip flags as needed:

```powershell
# Example: Skip certificate generation if already exists
./deploy.ps1 -Upgrade -SkipGenerateCertificate

# Example: Skip resource group creation
./deploy.ps1 -Upgrade -SkipCreateResourceGroup
```

#### Option B: Manual Logic App Update

If you prefer to manually update the Logic App (useful for review before applying changes):

1. Generate the Logic App JSON definition:
   ```powershell
   ./generateProcessProvisionRequest.ps1
   ```
   
   The script will:
   - Connect to SharePoint using the PnP app and certificate from your `parameters.json`
   - Automatically retrieve the list IDs from your Bestillingsportalen site
   - Generate `ProcessProvisionRequest.json` with all values populated
   - Prompt for your PnP certificate password if needed

2. (Optional) Generate without connecting to SharePoint:
   ```powershell
   ./generateProcessProvisionRequest.ps1 -SkipListIds
   ```
   This creates a file with placeholder values that you'll need to manually replace.

3. Open the generated file and review the changes

4. In Azure Portal:
   - Navigate to your ProcessProvisionRequest Logic App
   - Click "Logic app code view"
   - Copy the entire content from `ProcessProvisionRequest.json`
   - Paste it into the Logic App code view (replace all existing code)
   - Click "Save"

5. If you used Option B, you still need to apply the PnP template manually:
   ```powershell
   # Connect using your PnP app credentials
   Connect-PnPOnline -Url "https://yourtenant.sharepoint.com/sites/bestillingsportalen" -ClientId <your-pnp-app-id> -CertificatePath <path-to-cert>
   Invoke-PnPSiteTemplate -Path "../Templates/Bestillingsportalen.xml" -ClearNavigation
   ```

### Step 3: What Happens During Upgrade

The script will:

1. **Validate Parameters** - Check your parameters.json configuration
2. **Connect to Services** - Sign in to Azure, Azure CLI, and PnP PowerShell
3. **Apply PnP Template** - Update site structure WITHOUT modifying list data
4. **Retrieve List IDs** - Get necessary list identifiers for Logic App configuration
5. **Deploy ProcessProvisionRequest** - Replace the Logic App with the latest version
6. **Complete** - Show success message

### Step 4: Post-Upgrade Verification

After the upgrade completes:

1. **Verify Site Access**
   - Navigate to your Bestillingsportalen site
   - Confirm the site loads correctly

2. **Check List Data**
   - Open Provisioning Types list - verify all your custom types are still there
   - Check Provisioning Request Settings - confirm settings are preserved
   - Review any in-progress or completed provisioning requests

3. **Test the Workflow**
   - Create a test provisioning request (use a simple site type)
   - Monitor the Logic App execution in Azure Portal
   - Verify the site gets created successfully

4. **Review Logic App**
   - Go to Azure Portal → Your Resource Group → ProcessProvisionRequest Logic App
   - Check the run history
   - Verify it's using the latest definition

5. **Check for New Features**
   - Review what's new in this version
   - Test any new functionality
   - Update your documentation if needed

## Common Upgrade Scenarios

### Upgrading from v1.x to v2.x

If you're upgrading to a major version:
1. Review the [Version2.md](Version2.md) documentation for breaking changes
2. Plan for any data migrations needed
3. Consider testing in a dev environment first

### Applying Hotfixes

For minor bug fixes:
1. Pull the latest changes from the repository
2. Run with `-Upgrade`
3. Verify the fix is applied

### Adding New Features

When new features are added to the template:
1. The PnP template will add new fields/lists automatically
2. You may need to manually configure new provisioning types
3. Update your Power App if UI changes are needed

## Troubleshooting

### Issue: "List not found" Error

**Cause:** The list structure doesn't match expected schema.

**Solution:**
1. Verify you're running against the correct site
2. Check that initial deployment completed successfully
3. May need to reapply the full template without `-Upgrade`

### Issue: Logic App Deployment Fails

**Cause:** Missing parameters or changed resource names.

**Solution:**
1. Verify `parameters.json` has correct values
2. Check that the automation account name matches (default: `bestillingsportalen-auto`)
3. Ensure list IDs are being retrieved correctly

### Issue: PnP Template Application Fails

**Cause:** Permission issues or conflicts with customizations.

**Solution:**
1. Confirm you're a Site Collection Administrator
2. Check for conflicting customizations
3. Review PnP PowerShell connection and permissions

### Issue: Existing Requests Stop Working

**Cause:** Logic App update might have introduced breaking changes.

**Solution:**
1. Check Logic App run history for specific errors
2. Review the [CHANGELOG.md](CHANGELOG.md) for breaking changes
3. May need to update Runbooks or API connections
4. Check that all parameters are properly configured

## Rollback Procedure

If the upgrade causes issues:

### Rollback the Logic App

1. Go to Azure Portal → Resource Group → ProcessProvisionRequest Logic App
2. Click "Versions" in the left menu
3. Select the previous working version
4. Click "Promote" to make it active

### Rollback the PnP Template

Unfortunately, PnP template changes cannot be easily rolled back. Options:

1. **Manual Reversion:**
   - Identify what changed
   - Manually revert fields/views/etc.

2. **Restore from Backup:**
   - If you have a site backup, restore it
   - This will lose any requests created since backup

3. **Reapply Previous Version:**
   - Checkout previous git commit
   - Run `./deploy.ps1 -Upgrade` with the older template

## Best Practices

1. **Test First**
   - If possible, test the upgrade in a dev/test environment
   - Verify everything works before upgrading production

2. **Schedule Maintenance Window**
   - Notify users of the upgrade
   - Perform during off-hours if possible
   - Plan for 30-60 minutes of work

3. **Keep Parameters Updated**
   - Maintain your `parameters.json` file
   - Document any custom values

4. **Monitor After Upgrade**
   - Watch Logic App runs for the first few hours
   - Be available to address user questions
   - Check for any error notifications

5. **Document Your Customizations**
   - Keep a record of custom provisioning types
   - Note any template modifications
   - Track manual configuration changes

## Upgrade Checklist

Use this checklist for your upgrade:

- [ ] Backup current environment
- [ ] Review release notes and changelog
- [ ] Update local repository to latest version
- [ ] Verify `parameters.json` is current
- [ ] Notify users of maintenance window
- [ ] Run `./deploy.ps1 -Upgrade`
- [ ] Verify site loads correctly
- [ ] Check all lists and data are intact
- [ ] Test Logic App with a sample request
- [ ] Review Logic App run history
- [ ] Test new features (if any)
- [ ] Update documentation
- [ ] Notify users upgrade is complete

## Getting Help

If you encounter issues during upgrade:

1. Check the [Error-handling.md](Error-handling.md) documentation
2. Review the Logic App run history in Azure Portal
3. Check the [CHANGELOG.md](CHANGELOG.md) for known issues
4. Consult the [README.md](README.md) for general guidance
5. Open an issue in the repository with:
   - Version you're upgrading from/to
   - Error messages
   - Steps to reproduce
   - Screenshots if applicable

## Next Steps

After a successful upgrade:

1. **Review New Features** - Check the changelog for what's new
2. **Update Your Documentation** - Record the new version number
3. **Train Users** - If there are UI or workflow changes
4. **Plan Next Upgrade** - Stay current with future releases
5. **Contribute Back** - Share your feedback and improvements

---

**Related Documentation:**
- [README.md](README.md) - Main documentation
- [Deployment-guide.md](Deployment-guide.md) - Full deployment process
- [CHANGELOG.md](CHANGELOG.md) - Version history
- [Error-handling.md](Error-handling.md) - Troubleshooting guide
