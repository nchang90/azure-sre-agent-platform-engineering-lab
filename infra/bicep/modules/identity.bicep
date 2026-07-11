// ─────────────────────────────────────────────────────────────────────────────
// Platform user-assigned managed identity.
//
// S1's single foundational identity. Later layers (Terraform / S3) attach the
// SRE Agent and applications to it and grant the agent-specific RBAC there.
// ─────────────────────────────────────────────────────────────────────────────

@description('Azure region for the identity.')
param location string

@description('Stable token used to make resource names unique within the subscription.')
param resourceToken string

@description('Tags applied to the identity.')
param tags object = {}

#disable-next-line BCP073
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-sre-agent-${resourceToken}'
  location: location
  tags: tags
  properties: { isolationScope: 'Regional' }
}

output id string = identity.id
output name string = identity.name
output principalId string = identity.properties.principalId
output clientId string = identity.properties.clientId
