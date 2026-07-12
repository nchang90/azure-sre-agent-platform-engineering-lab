// ─────────────────────────────────────────────────────────────────────────────
// Log Analytics workspace + workspace-based Application Insights.
//
// The observability foundation: the Container Apps environment ships its logs
// here, and the SRE Agent's log configuration points at the App Insights
// instance.
// ─────────────────────────────────────────────────────────────────────────────

@description('Azure region for the workspace and App Insights.')
param location string

@description('Stable token used to make resource names unique within the subscription.')
param resourceToken string

@description('Tags applied to both resources.')
param tags object = {}

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${resourceToken}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'SreAgent'
    WorkspaceResourceId: law.id
  }
}

output workspaceId string = law.id
output workspaceName string = law.name
output customerId string = law.properties.customerId
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output appInsightsAppId string = appInsights.properties.AppId
