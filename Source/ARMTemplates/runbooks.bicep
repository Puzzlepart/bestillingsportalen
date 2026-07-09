// All Azure Automation runbooks for the solution, plus the PowerShell 7.4 runtime
// environment they run in (with PnP.PowerShell 3.x - the classic PowerShell 7.2
// module model tops out at PnP.PowerShell 2.x, which is why runtime environments
// are used).
//
// Kept separate from azureresources.bicep so deploy.ps1 can deploy the runbooks
// alone in upgrade mode without re-running the full azureresources stack (key
// vault, automation account, API connections, etc.).
//
// PLACEHOLDER URIs: until this repo is public, upstream pnp/provision-assist-m365
// content is used just so each runbook resource can be provisioned. After the
// first deploy you MUST open Azure Portal -> Automation Account -> Runbooks and
// paste the real contents from Source/Runbooks/ into ConfigureSpace and
// AddGuestToSite (see the Deployment guide, step 6a). GetSiteTemplates is
// identical to upstream and needs no paste. Once this repo is public, change each
// `uri` to point to our raw URL and bump `version` to force re-import on next
// deploy - existing manually-pasted content is preserved on re-deploy as long as
// the version is unchanged.

@description('Name of the existing Azure Automation Account')
param automationAccountName string

@description('Azure region for the runbook resources (must match the automation account)')
param location string

@description('Name of the PowerShell 7.4 runtime environment the runbooks run in')
param runtimeEnvironmentName string = 'bestillingsportalen-ps74'

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' existing = {
  name: automationAccountName
}

// PowerShell 7.4 runtime environment with PnP.PowerShell 3.x for all runbooks
resource runtimeEnvironment 'Microsoft.Automation/automationAccounts/runtimeEnvironments@2024-10-23' = {
  parent: automationAccount
  name: runtimeEnvironmentName
  location: location
  properties: {
    runtime: {
      language: 'PowerShell'
      version: '7.4'
    }
    defaultPackages: {
      az: '12.3.0'
    }
    description: 'PowerShell 7.4 with PnP.PowerShell for the Bestillingsportalen runbooks'
  }
}

resource pnpPowerShellPackage 'Microsoft.Automation/automationAccounts/runtimeEnvironments/packages@2024-10-23' = {
  parent: runtimeEnvironment
  name: 'PnP.PowerShell'
  location: location
  properties: {
    contentLink: {
      uri: 'https://devopsgallerystorage.blob.core.windows.net/packages/pnp.powershell.3.2.0.nupkg'
      version: '3.2.0'
    }
  }
}

resource configureSpaceRunbook 'Microsoft.Automation/automationAccounts/runbooks@2024-10-23' = {
  parent: automationAccount
  name: 'ConfigureSpace'
  location: location
  properties: {
    logVerbose: true
    logProgress: true
    runbookType: 'PowerShell'
    runtimeEnvironment: runtimeEnvironment.name
    publishContentLink: {
      uri: 'https://raw.githubusercontent.com/pnp/provision-assist-m365/main/Source/Runbooks/ConfigureSpace.ps1'
      version: '1.0.0.0'
    }
  }
  dependsOn: [
    pnpPowerShellPackage
  ]
}

resource getSiteTemplatesRunbook 'Microsoft.Automation/automationAccounts/runbooks@2024-10-23' = {
  parent: automationAccount
  name: 'GetSiteTemplates'
  location: location
  properties: {
    logVerbose: true
    logProgress: true
    runbookType: 'PowerShell'
    runtimeEnvironment: runtimeEnvironment.name
    publishContentLink: {
      uri: 'https://raw.githubusercontent.com/pnp/provision-assist-m365/main/Source/Runbooks/GetSiteTemplates.ps1'
      version: '1.0.0.0'
    }
  }
  dependsOn: [
    pnpPowerShellPackage
  ]
}

resource addGuestToSiteRunbook 'Microsoft.Automation/automationAccounts/runbooks@2024-10-23' = {
  parent: automationAccount
  name: 'AddGuestToSite'
  location: location
  properties: {
    logVerbose: true
    logProgress: true
    runbookType: 'PowerShell'
    runtimeEnvironment: runtimeEnvironment.name
    publishContentLink: {
      uri: 'https://raw.githubusercontent.com/pnp/provision-assist-m365/main/Source/Runbooks/ConfigureSpace.ps1'
      version: '1.0.0.0'
    }
  }
  dependsOn: [
    pnpPowerShellPackage
  ]
}
