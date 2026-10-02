// ─────────────────────────────────────────────────────────────────────────────
// Key Vault locked to the agent subnet — the S1 VNet-integration proof point.
//
// The vault firewall denies everything except the agent subnet, reached through
// a Microsoft.KeyVault service endpoint (network.bicep). For the agent to read
// it, both must line up (miss one and the vault returns 403 ForbiddenByFirewall):
//   1. the agent is VNet-injected (sre-agent.bicep → vnetConfiguration)
//   2. the agent subnet is in the vault's virtualNetworkRules
//
// Cost: Standard vault (per-operation, ~free at lab volume). Service endpoints
// are free — no private endpoint or private DNS zone.
// ─────────────────────────────────────────────────────────────────────────────

@description('Azure region for the vault.')
param location string

@description('Stable token used to make resource names unique within the subscription.')
param resourceToken string

@description('Tags applied to all resources.')
param tags object = {}

@description('Resource ID of the agent subnet allowed through the vault firewall.')
param agentSubnetId string

@description('Principal ID of the agent identity. Granted Key Vault Secrets User.')
param agentPrincipalId string

// Key Vault Secrets User — read secret values only.
var secretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

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
    // Must stay Enabled for the firewall rules below to apply.
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'None'
      virtualNetworkRules: [
        { id: agentSubnetId }
      ]
    }
  }
}

// Created through ARM (control plane), so it works with the firewall closed.
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

output id string = vault.id
output name string = vault.name
output uri string = vault.properties.vaultUri
