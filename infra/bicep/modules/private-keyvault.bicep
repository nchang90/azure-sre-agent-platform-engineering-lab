// ─────────────────────────────────────────────────────────────────────────────
// Private Key Vault — the S1 VNet-integration proof point.
//
// Public network access is disabled, so the only way in is the private endpoint.
// For the agent to reach it, all four of these must line up (miss one and the
// FQDN resolves to the vault's public IP, which the vault refuses):
//   1. the agent is VNet-injected (sre-agent.bicep → vnetConfiguration)
//   2. a private endpoint (groupId 'vault') in the VNet
//   3. the privatelink.vaultcore.azure.net zone holds the endpoint's A record
//   4. that zone is linked to the agent's VNet
//
// Cost: Standard vault (per-operation, ~free at lab volume), one private
// endpoint (~$7.30/month) and one private DNS zone (~$0.50/month).
// ─────────────────────────────────────────────────────────────────────────────

@description('Azure region for the vault and private endpoint.')
param location string

@description('Stable token used to make resource names unique within the subscription.')
param resourceToken string

@description('Tags applied to all resources.')
param tags object = {}

@description('Resource ID of the VNet the private DNS zone is linked to.')
param vnetId string

@description('Resource ID of the subnet that holds the private endpoint.')
param privateEndpointSubnetId string

@description('Principal ID of the agent identity. Granted Key Vault Secrets User.')
param agentPrincipalId string

// Key Vault Secrets User — read secret values only.
var secretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
var privateDnsZoneName = 'privatelink.vaultcore.azure.net'

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${resourceToken}'
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    // Short retention so `azd down --purge` and redeploys stay quick.
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'None'
    }
  }
}

// Created through ARM (control plane), so it works with public access disabled.
// The value is a placeholder; the demo is about reaching it, not what it holds.
resource demoSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: vault
  name: 'orders-db-connection'
  properties: {
    value: 'Server=orders-db.internal;Database=orders;Authentication=ManagedIdentity'
    contentType: 'text/plain'
  }
}

resource secretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, agentPrincipalId, secretsUserRoleId)
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', secretsUserRoleId)
    principalId: agentPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: tags
}

// Without this link the vault FQDN resolves to a public IP from the agent.
resource dnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: 'link-sre-agent-vnet'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-kv-${resourceToken}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'pe-kv-${resourceToken}'
        properties: {
          privateLinkServiceId: vault.id
          groupIds: [ 'vault' ]
        }
      }
    ]
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'vaultcore'
        properties: { privateDnsZoneId: privateDnsZone.id }
      }
    ]
  }
}

output id string = vault.id
output name string = vault.name
output uri string = vault.properties.vaultUri
output dnsLinkId string = dnsLink.id
