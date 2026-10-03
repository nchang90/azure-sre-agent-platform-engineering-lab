# Mirrors microsoft/sre-agent examples/vnet-integrated-keyvault:
# VNet with a delegated /27 agent subnet and a /27 private-endpoint subnet, no NSG.
locals {
  vnet_enabled        = var.enable_vnet || var.existing_subnet_id != ""
  create_vnet         = var.enable_vnet && var.existing_subnet_id == ""
  effective_subnet_id = var.existing_subnet_id != "" ? var.existing_subnet_id : try(azurerm_subnet.agent[0].id, "")
}

resource "azurerm_virtual_network" "agent" {
  count               = local.create_vnet ? 1 : 0
  name                = "vnet-${local.suffix}"
  resource_group_name = azurerm_resource_group.agent.name
  location            = var.location
  address_space       = [var.vnet_address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "agent" {
  count                = local.create_vnet ? 1 : 0
  name                 = "agent-subnet"
  resource_group_name  = azurerm_resource_group.agent.name
  virtual_network_name = azurerm_virtual_network.agent[0].name
  address_prefixes     = [var.agent_subnet_prefix]

  delegation {
    name = "app-env-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "pe" {
  count                = local.create_vnet ? 1 : 0
  name                 = "pe-subnet"
  resource_group_name  = azurerm_resource_group.agent.name
  virtual_network_name = azurerm_virtual_network.agent[0].name
  address_prefixes     = [var.pe_subnet_prefix]
}
