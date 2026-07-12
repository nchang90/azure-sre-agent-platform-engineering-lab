targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the azd environment. Used to derive resource names and tags.')
param environmentName string

@minLength(2)
@maxLength(63)
@description('SRE Agent name (lowercase alphanumeric with hyphens).')
param agentName string = 'sre-agent'

@description('Azure region. Restricted to regions supported by the SRE Agent resource provider.')
@allowed([
  'swedencentral'
  'uksouth'
  'eastus2'
  'australiaeast'
])
param location string = 'eastus2'

@description('Object ID of the deploying user/service principal. When set, it is granted SRE Agent Administrator on the agent. azd populates AZURE_PRINCIPAL_ID automatically.')
param principalId string = ''

@description('Agent access level. Low = read-only investigation, High = can take actions.')
@allowed([
  'Low'
  'High'
])
param accessLevel string = 'Low'

@description('Agent action mode. Review = human approval, Automatic = agent acts independently.')
@allowed([
  'Review'
  'Automatic'
])
param actionMode string = 'Review'

@description('Resource groups the agent is granted knowledge-graph access to. Defaults to the S1 resource group.')
param targetResourceGroups array = []

@description('Additional tags applied to every resource.')
param tags object = {}

var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var resourceGroupName = 'rg-${environmentName}'

var defaultTags = union(tags, {
  'azd-env-name': environmentName
  workload: 'sre-agent'
  layer: 's1-base-infra'
})

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: defaultTags
}

// ── Foundation modules (resource-group scope) ─────────────────────────────────
module identity 'modules/identity.bicep' = {
  name: 'identity'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    tags: defaultTags
  }
}

module monitoring 'modules/loganalytics.bicep' = {
  name: 'loganalytics'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    tags: defaultTags
  }
}

module containerApps 'modules/containerapps.bicep' = {
  name: 'containerapps'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    tags: defaultTags
    logAnalyticsWorkspaceName: monitoring.outputs.workspaceName
  }
}

module sreAgent 'modules/sre-agent.bicep' = {
  name: 'sre-agent'
  scope: rg
  params: {
    location: location
    agentName: agentName
    identityId: identity.outputs.id
    identityPrincipalId: identity.outputs.principalId
    principalId: principalId
    accessLevel: accessLevel
    actionMode: actionMode
    targetResourceGroups: targetResourceGroups
    appInsightsAppId: monitoring.outputs.appInsightsAppId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    tags: defaultTags
  }
}

// ── Outputs for Terraform / scripts ───────────────────────────────────────────
// azd writes these to .azure/<env>/.env (UPPER_SNAKE_CASE). The Terraform layer
// reads them to wire the application/logic resources onto this foundation.
output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId
output AZURE_TENANT_ID string = subscription().tenantId

output SRE_MANAGED_IDENTITY_ID string = identity.outputs.id
output SRE_MANAGED_IDENTITY_PRINCIPAL_ID string = identity.outputs.principalId
output SRE_MANAGED_IDENTITY_CLIENT_ID string = identity.outputs.clientId

output SRE_LOG_ANALYTICS_WORKSPACE_ID string = monitoring.outputs.workspaceId
output SRE_LOG_ANALYTICS_CUSTOMER_ID string = monitoring.outputs.customerId
output SRE_APP_INSIGHTS_CONNECTION_STRING string = monitoring.outputs.appInsightsConnectionString
output SRE_APP_INSIGHTS_APP_ID string = monitoring.outputs.appInsightsAppId

output SRE_CONTAINER_APPS_ENVIRONMENT_ID string = containerApps.outputs.id
output SRE_CONTAINER_APPS_ENVIRONMENT_NAME string = containerApps.outputs.name

output SRE_AGENT_ID string = sreAgent.outputs.id
output SRE_AGENT_NAME string = sreAgent.outputs.name
