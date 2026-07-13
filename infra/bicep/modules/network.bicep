// ─────────────────────────────────────────────────────────────────────────────
// Delegated subnet for the Container Apps managed environment inside the
// existing AKS virtual network.
// ─────────────────────────────────────────────────────────────────────────────

@description('Name of the existing virtual network to place the agent subnet in.')
param virtualNetworkName string

@description('Delegated subnet address prefix for the Container Apps managed environment.')
param infrastructureSubnetPrefix string = '10.50.1.0/24'

resource vnet 'Microsoft.Network/virtualNetworks@2022-07-01' existing = {
  name: virtualNetworkName
}

resource infrastructureSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-07-01' = {
  parent: vnet
  name: 'snet-sre-agent'
  properties: {
    addressPrefix: infrastructureSubnetPrefix
    delegations: [
      {
        name: 'Microsoft.App.environments'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
  }
}

output id string = infrastructureSubnet.id
output virtualNetworkId string = vnet.id
output name string = infrastructureSubnet.name
