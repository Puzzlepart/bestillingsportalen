// Runbooks owned by this repo (as opposed to upstream pnp/provision-assist-m365 ones
// like ConfigureSpace and GetSiteTemplates which live in azureresources.bicep).
//
// Kept separate so deploy.ps1 can deploy these alone in upgrade mode without re-running
// the full azureresources stack (key vault, automation account, API connections, etc.).
//
// PLACEHOLDER URIs: until this repo is public, we reuse ConfigureSpace.ps1 from the
// upstream repo just so each resource can be provisioned. After the first deploy you
// MUST open Azure Portal -> Automation Account -> Runbooks -> <runbook> -> Edit and paste
// the real contents from the corresponding file under Source/Runbooks/. Once this repo
// is public, change each `uri` to point to our raw URL and bump `version` to force
// re-import on next deploy.

@description('Name of the existing Azure Automation Account')
param automationAccountName string

@description('Azure region for the runbook resources (must match the automation account)')
param location string

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' existing = {
  name: automationAccountName
}

resource addGuestToSiteRunbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'AddGuestToSite'
  location: location
  properties: {
    logVerbose: true
    logProgress: true
    runbookType: 'PowerShell72'
    publishContentLink: {
      uri: 'https://raw.githubusercontent.com/pnp/provision-assist-m365/main/Source/Runbooks/ConfigureSpace.ps1'
      version: '1.0.0.0'
    }
  }
}
