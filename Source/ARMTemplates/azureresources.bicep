param location string = resourceGroup().location
param automationAccountName string = 'bestillingsportalen-auto'
param uamiName string = 'bestillingsportalen-uami'
param tenantId string
param logoUrl string

// The solution no longer deploys a Key Vault. Its only purpose was to hold the client
// secret and non-MFA service account credentials for the delegated ROPC flow that
// applied sensitivity labels. Labels are now applied app-only with the automation
// account's managed identity via Set-PnPTenantSite -SensitivityLabel, so there are no
// runtime secrets left to store. Existing installations must delete the vault and the
// Entra ID app manually - ARM does not remove resources dropped from a template.
// See Upgrade.md and Sensitivity-labels.md.

// User-assigned managed identity shared by all logic apps. Used for Graph/SharePoint
// HTTP actions and the Azure Automation API connection, replacing the Entra ID app
// client secret and certificate.
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uamiName
  location: location
}

// Automation account
resource automationAccount 'Microsoft.Automation/automationAccounts@2022-08-08' = {
  name: automationAccountName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Free'
    }
  }
}

// All runbooks (ConfigureSpace, GetSiteTemplates, AddGuestToSite) plus the
// PowerShell 7.4 runtime environment they run in (with PnP.PowerShell 3.x) are
// defined in runbooks.bicep, which deploy.ps1 deploys in both full and upgrade
// mode - so runbook/runtime changes reach existing environments via -Upgrade
// without re-running the full azureresources stack.

// RBAC so the logic apps (via the user-assigned managed identity) can start runbook
// jobs and read job output through the Azure Automation API connection.
resource uamiJobOperatorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(automationAccount.id, uami.id, 'AutomationJobOperator')
  scope: automationAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4fe576fe-1146-4730-92eb-48519fa6bf9f') // Automation Job Operator
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource uamiRunbookOperatorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(automationAccount.id, uami.id, 'AutomationRunbookOperator')
  scope: automationAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5fb5aef8-1081-4b8e-bb16-9d5d0385bab5') // Automation Runbook Operator
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Variables
resource tenantIdVariable 'Microsoft.Automation/automationAccounts/variables@2019-06-01' = {
  parent: automationAccount
  name: 'tenantId'
  properties: {
    value: '"${tenantId}"'
    isEncrypted: false
  }
}

resource logoUrlVariable 'Microsoft.Automation/automationAccounts/variables@2019-06-01' = {
  parent: automationAccount
  name: 'logoUrl'
  properties: {
    value: '"${logoUrl}"'
    isEncrypted: false
  }
}

output uamiResourceId string = uami.id
output uamiPrincipalId string = uami.properties.principalId



