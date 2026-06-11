param location string = resourceGroup().location
param automationAccountName string = 'bestillingsportalen-auto'
param uamiName string = 'bestillingsportalen-uami'
param tenantId string
param appClientId string
@secure()
param appSecret string
param logoUrl string
param keyVaultName string
param saUsername string
@secure()
param saPassword string

// User-assigned managed identity shared by all logic apps. Used for Graph/SharePoint
// HTTP actions and the Key Vault/Azure Automation API connections, replacing the
// Entra ID app client secret and certificate.
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uamiName
  location: location
}

// Key vault & secrets
resource keyVault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: keyVaultName
  location: location
  properties: {
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    tenantId: tenantId
    accessPolicies: [
      {
        tenantId: tenantId
        objectId: uami.properties.principalId
        permissions: {
          secrets: [
            'list'
            'get'
          ]
        }
      }
    ]
    sku: {
      name: 'standard'
      family: 'A'
    }
  }
}

resource keyVaultAppIdSecret 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  parent: keyVault
  name:  'appid'
  properties: {
    value: appClientId
  }
}

resource keyVaultAppSecret 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  parent: keyVault
  name:  'appSecret'
  properties: {
    value: appSecret
  }
}

resource keyVaultsaUsernameSecret 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  parent: keyVault
  name:  'sausername'
  properties: {
    value: saUsername
  }
}

resource keyVaultsaPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  parent: keyVault
  name:  'sapassword'
  properties: {
    value: saPassword
  }
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

// Modules
resource Az_Accounts 'Microsoft.Automation/automationAccounts/powerShell72Modules@2023-11-01' = {
  name: 'Az.Accounts'
  location: location
  parent: automationAccount
  properties: {
    contentLink: {
      uri: 'https://devopsgallerystorage.blob.core.windows.net/packages/az.accounts.1.6.2.nupkg'
      version: '1.6.2'
    }
  }
}

resource PnP_PowerShell 'Microsoft.Automation/automationAccounts/powerShell72Modules@2023-11-01' = {
  name: 'PnP.PowerShell'
  location: location
  parent: automationAccount
  properties: {
    contentLink: {
      uri: 'https://devopsgallerystorage.blob.core.windows.net/packages/pnp.powershell.2.4.0.nupkg'
      version: '2.4.0'
    }
  }
}

// Runbooks
resource getSiteTemplatesRunbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'GetSiteTemplates'
  location: location
  properties: {
    logVerbose: true
    logProgress: true
    runbookType: 'PowerShell72'
    publishContentLink: {
      uri: 'https://raw.githubusercontent.com/pnp/provision-assist-m365/main/Source/Runbooks/GetSiteTemplates.ps1'
      version: '1.0.0.0'
    }
  }
}

resource configureSpaceRunbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'ConfigureSpace'
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

// AddGuestToSite and other runbooks owned by this repo are defined in runbooks.bicep
// so they can be deployed independently in upgrade mode without re-running the full
// azureresources stack.

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



