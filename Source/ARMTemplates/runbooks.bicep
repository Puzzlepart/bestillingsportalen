// All Azure Automation runbooks for the solution, plus the PowerShell 7.4 runtime
// environment they run in (with PnP.PowerShell 3.x - the classic PowerShell 7.2
// module model tops out at PnP.PowerShell 2.x, which is why runtime environments
// are used).
//
// Kept separate from azureresources.bicep so deploy.ps1 can deploy the runbooks
// alone in upgrade mode without re-running the full azureresources stack (key
// vault, automation account, API connections, etc.).
//
// The runbooks are created here as empty shells (draft) - deploy.ps1 uploads the
// actual content from Source/Runbooks/ via the management API right after this
// template is deployed, and publishes each runbook. No manual paste step, and the
// content is always in sync with the repo (NOTE: this also means portal-side edits
// to the runbooks are overwritten on every deploy/upgrade - customisations belong
// in the repo).

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
  properties: {
    contentLink: {
      // PowerShell Gallery's artifact storage - not an ARM environment endpoint,
      // so the environment() function has no equivalent (linter false positive)
      #disable-next-line no-hardcoded-env-urls
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
    draft: {}
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
    draft: {}
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
    draft: {}
  }
  dependsOn: [
    pnpPowerShellPackage
  ]
}
