// ─────────────────────────────────────────────────────────────────────────────
// Dedicated virtual network and delegated subnet for the Container Apps
// managed environment.
// ─────────────────────────────────────────────────────────────────────────────

@description('Azure region for the network resources.')
param location string

@description('Stable token used to make resource names unique within the subscription.')
param resourceToken string

@description('Tags applied to the network resources.')
param tags object = {}

@description('Virtual network address space.')
param virtualNetworkAddressPrefix string = '10.50.0.0/16'

@description('Delegated subnet address prefix for the Container Apps managed environment.')
param infrastructureSubnetPrefix string = '10.50.1.0/24'

resource vnet 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  name: 'vnet-${resourceToken}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkAddressPrefix
      ]
    }
  }
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
