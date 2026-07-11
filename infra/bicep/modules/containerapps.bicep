// ─────────────────────────────────────────────────────────────────────────────
// Container Apps managed environment, wired to the Log Analytics workspace.
// ─────────────────────────────────────────────────────────────────────────────

@description('Azure region for the environment.')
param location string

@description('Stable token used to make resource names unique within the subscription.')
param resourceToken string

@description('Tags applied to the environment.')
param tags object = {}

@description('Name of the Log Analytics workspace the environment ships its logs to.')
param logAnalyticsWorkspaceName string

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource containerAppsEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${resourceToken}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: law.properties.customerId
        sharedKey: law.listKeys().primarySharedKey
      }
    }
  }
}

output id string = containerAppsEnv.id
output name string = containerAppsEnv.name
