// ─────────────────────────────────────────────────────────────────────────────
// VNet for SRE Agent VNet integration.
//
// Mirrors Microsoft's vnet-integrated-keyvault example (microsoft/sre-agent →
// sreagent-templates/examples): one VNet, two /27 subnets.
//   • snet-sre-agent — delegated to Microsoft.App/environments; the agent and
//     its sandbox egress through it. /27 is the minimum the RP accepts.
//   • snet-pe        — holds private endpoints for locked-down resources.
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

@description('VNet address space. Room for the two /27 subnets below.')
param addressSpace string = '10.30.0.0/26'

@description('Agent subnet range (/27 or larger).')
param agentSubnetPrefix string = '10.30.0.0/27'

@description('Private endpoint subnet range.')
param privateEndpointSubnetPrefix string = '10.30.0.32/27'

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
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: { serviceName: 'Microsoft.App/environments' }
            }
          ]
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output agentSubnetId string = vnet.properties.subnets[0].id
output privateEndpointSubnetId string = vnet.properties.subnets[1].id
