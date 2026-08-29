@description('Location for the Front Door resource.')
param location string = 'global'

@description('Resource token for naming.')
param resourceToken string

@description('Container Apps Environment Name.')
param containerAppsEnvironmentName string

@description('Log Analytics Workspace ID for diagnostic settings.')
param logAnalyticsWorkspaceId string

@description('Tags applied to all resources.')
param tags object = {}

@description('SKU for Front Door. Standard or Premium.')
param skuName string = 'Standard_AzureFrontDoor'

@description('Health probe path.')
param healthProbePath string = '/health'

@description('Health probe protocol.')
param healthProbeProtocol string = 'Http'

@description('Session affinity enabled.')
param sessionAffinityEnabled bool = false

var frontDoorName = 'fd-${resourceToken}'
var frontendEndpointName = 'fep-${resourceToken}'
var originGroupName = 'og-${resourceToken}'
var originName = 'origin-${resourceToken}'
var routingRuleName = 'rr-default'

// Parse Container Apps Environment FQDN
var containerAppsEnvFqdn = '${containerAppsEnvironmentName}.eastus2.azurecontainerapps.io'

resource frontDoor 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: frontDoorName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    originResponseTimeoutSeconds: 30
  }
}

resource frontendEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  parent: frontDoor
  name: frontendEndpointName
  properties: {
    enabledState: 'Enabled'
  }
}

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  parent: frontDoor
  name: originGroupName
  properties: {
    loadBalancingSettings: {
      additionalLatencyInMilliseconds: 50
      sampleSize: 4
      successfulSamplesRequired: 3
    }
    healthProbeSettings: {
      probePath: healthProbePath
      probeProtocol: healthProbeProtocol
      probeIntervalInSeconds: 100
    }
    sessionAffinityState: sessionAffinityEnabled ? 'Enabled' : 'Disabled'
  }
}

resource origin 'Microsoft.Cdn/profiles/origins@2024-02-01' = {
  parent: frontDoor
  name: originName
  properties: {
    hostName: containerAppsEnvFqdn
    httpPort: 80
    httpsPort: 443
    originHostHeader: containerAppsEnvFqdn
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    sharedPrivateLinkResource: null
  }
  dependsOn: [originGroup]
}

resource routingRule 'Microsoft.Cdn/profiles/routes@2024-02-01' = {
  parent: frontDoor
  name: routingRuleName
  properties: {
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    originGroup: {
      id: originGroup.id
    }
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
    compressionSettings: {
      isCompressionEnabled: true
      contentTypesToCompress: [
        'application/json'
        'application/xml'
        'text/html'
        'text/plain'
        'text/xml'
        'text/css'
        'application/javascript'
      ]
    }
  }
  dependsOn: [
    origin
    frontendEndpoint
  ]
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: frontDoor
  name: 'frontdoor-diagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        category: 'FrontdoorAccessLog'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'FrontdoorHealthProbeLog'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'FrontdoorWebApplicationFirewallLog'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Outputs
output id string = frontDoor.id
output name string = frontDoor.name
output hostName string = frontendEndpoint.properties.hostName
output frontendEndpointId string = frontendEndpoint.id
output originGroupId string = originGroup.id
output originId string = origin.id
output skuName string = skuName
