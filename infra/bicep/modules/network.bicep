// ─────────────────────────────────────────────────────────────────────────────
// VNet for SRE Agent VNet integration.
//
// Mirrors Microsoft's vnet-integrated-keyvault example (microsoft/sre-agent →
// sreagent-templates/examples): one VNet with a single /27 subnet,
// snet-sre-agent, delegated to Microsoft.App/environments. The agent and its
// sandbox egress through it. /27 is the minimum the RP accepts. A
// Microsoft.KeyVault service endpoint lets the vault firewall (keyvault.bicep)
// admit this subnet.
//
// Cost: VNets and subnets are free. No NSG, firewall or NAT gateway — package
// registries, GitHub and remote MCP go via the agent's managed path instead
// (see sre-agent.bicep), so nothing here needs paid internet egress.
// ─────────────────────────────────────────────────────────────────────────────

@description('Azure region. Must match the agent region.')
param location string

@description('Stable token used to make resource names unique within the subscription.')
param resourceToken string

@description('Tags applied to the VNet.')
param tags object = {}

@description('VNet address space.')
param addressSpace string = '10.30.0.0/27'

@description('Agent subnet range (/27 or larger).')
param agentSubnetPrefix string = '10.30.0.0/27'

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-sre-agent-${resourceToken}'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [ addressSpace ] }
    subnets: [
      {
        name: 'snet-sre-agent'
        properties: {
          addressPrefix: agentSubnetPrefix
          // New subnets default to private (no default outbound access). Keep it
          // on so sandbox calls to public Azure endpoints work without paying
          // for a NAT gateway.
          defaultOutboundAccess: true
          serviceEndpoints: [
            { service: 'Microsoft.KeyVault' }
          ]
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: { serviceName: 'Microsoft.App/environments' }
            }
          ]
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output agentSubnetId string = vnet.properties.subnets[0].id
