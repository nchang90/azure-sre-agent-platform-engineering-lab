// ─────────────────────────────────────────────────────────────────────────────
// Base SRE Agent + the RBAC it needs to read the resource group.
//
// Mirrors Microsoft's official agent-core.bicep (microsoft/sre-agent →
// sreagent-templates/bicep). The agent runs as the platform identity, reads
// metrics/logs across its target resource groups for the knowledge graph, and
// ships telemetry to the App Insights instance from loganalytics.bicep.
// ─────────────────────────────────────────────────────────────────────────────

@description('Azure region for the agent.')
param location string

@description('SRE Agent name.')
param agentName string

@description('Resource ID of the platform managed identity.')
param identityId string

@description('Principal ID of the platform managed identity.')
param identityPrincipalId string

@description('Object ID of the deploying principal. Empty falls back to deployer(). Granted SRE Agent Administrator.')
param principalId string = ''

@description('Object IDs of additional users/groups granted SRE Agent Administrator.')
param adminPrincipalIds array = []

@description('Agent access level (Low | High).')
@allowed([ 'Low', 'High' ])
param accessLevel string

@description('Agent action mode (Review | Automatic).')
@allowed([ 'Review', 'Automatic' ])
param actionMode string

@description('Resource groups the agent gets knowledge-graph access to. Defaults to this RG.')
param targetResourceGroups array = []

@description('Application Insights App ID for the agent log configuration.')
param appInsightsAppId string

@description('Application Insights connection string for the agent log configuration.')
param appInsightsConnectionString string

@description('Tags applied to the agent.')
param tags object = {}

@description('Resource ID of a subnet delegated to Microsoft.App/environments. Empty = no VNet integration (Unrestricted egress).')
param subnetId string = ''

// ── Built-in role definition IDs ──────────────────────────────────────────────
var monitoringReaderRoleId = '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
var logAnalyticsReaderRoleId = '73c42c96-874c-492b-b04d-ab87d138a893'
// SRE Agent Administrator (data-plane admin on the agent resource).
var sreAgentAdminRoleId = 'e79298df-d852-4c6d-84f9-5d13249d1e55'

var effectiveAdminPrincipalId = empty(principalId) ? deployer().objectId : principalId
var effectiveTargetRgs = empty(targetResourceGroups) ? [ resourceGroup().name ] : targetResourceGroups
var managedResourceIds = [for rg in effectiveTargetRgs: subscriptionResourceId('Microsoft.Resources/resourceGroups', rg)]

// VNet integration. Agent/sandbox traffic to Azure resources goes through the
// subnet so it can reach private endpoints. Package registries, GitHub and
// remote MCP stay on the agent's managed path, so the VNet needs no NAT gateway
// or firewall rules for them.
var networkProperties = empty(subnetId) ? {} : {
  vnetConfiguration: {
    subnetResourceId: subnetId
  }
  sandboxConfiguration: {
    egress: {
      mode: 'AzureVNet'
      vnetConfiguration: {
        usePrivateDnsResolution: true
      }
      allowHttpMcpServerNetworkAccess: true
      allowedRegistries: [ 'pypi', 'npmjs' ]
      allowedCodeRepositories: [ 'Github' ]
      allowedHosts: []
    }
  }
}

// ── RBAC for the agent identity's knowledge-graph reads ───────────────────────
resource monitoringReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, identityId, monitoringReaderRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringReaderRoleId)
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource logReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, identityId, logAnalyticsReaderRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', logAnalyticsReaderRoleId)
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ── Base SRE Agent ────────────────────────────────────────────────────────────
#disable-next-line BCP081
resource sreAgent 'Microsoft.App/agents@2026-01-01' = {
  name: agentName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: { '${identityId}': {} }
  }
  properties: union(networkProperties, {
    knowledgeGraphConfiguration: {
      identity: identityId
      managedResources: managedResourceIds
    }
    actionConfiguration: {
      accessLevel: accessLevel
      identity: identityId
      mode: actionMode
    }
    logConfiguration: {
      applicationInsightsConfiguration: {
        appId: appInsightsAppId
        connectionString: appInsightsConnectionString
      }
    }
    upgradeChannel: 'Preview'
    monthlyAgentUnitLimit: 10000
    defaultModel: {
      provider: 'Anthropic'
      name: 'Automatic'
    }
    experimentalSettings: {
      EnableWorkspaceTools: true
      EnableHttpTriggers: true
      EnableV2AgentLoop: true
    }
  })
  dependsOn: [ monitoringReader, logReader ]
}

// Grant the deploying principal SRE Agent Administrator on the agent.
resource deployerAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sreAgent.id, effectiveAdminPrincipalId, sreAgentAdminRoleId)
  scope: sreAgent
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sreAgentAdminRoleId)
    principalId: effectiveAdminPrincipalId
  }
}

// Grant additional users/groups SRE Agent Administrator on the agent. The
// deployer is skipped so the same assignment is not declared twice.
resource extraAdmins 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for id in filter(adminPrincipalIds, id => id != effectiveAdminPrincipalId): {
  name: guid(sreAgent.id, id, sreAgentAdminRoleId)
  scope: sreAgent
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sreAgentAdminRoleId)
    principalId: id
  }
}]

// Grant the agent's UAMI SRE Agent Administrator (needed for HTTP-trigger callbacks).
resource uamiAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sreAgent.id, identityId, sreAgentAdminRoleId)
  scope: sreAgent
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sreAgentAdminRoleId)
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output id string = sreAgent.id
output name string = sreAgent.name
