locals {
  vnet_enabled        = var.enable_vnet || var.existing_subnet_id != ""
  create_vnet         = var.enable_vnet && var.existing_subnet_id == ""
  effective_subnet_id = var.existing_subnet_id != "" ? var.existing_subnet_id : try(azurerm_subnet.agent[0].id, "")

  network_config = local.vnet_enabled ? {
    networkConfiguration = {
      egressMode = "AzureVNet"
      subnetId   = local.effective_subnet_id
    }
  } : {}
}

resource "azurerm_virtual_network" "agent" {
  count               = local.create_vnet ? 1 : 0
  name                = "vnet-${local.suffix}"
  resource_group_name = azurerm_resource_group.agent.name
  location            = var.location
  address_space       = [var.vnet_address_space]
  tags                = var.tags
}

resource "azurerm_network_security_group" "agent" {
  count               = local.create_vnet ? 1 : 0
  name                = "nsg-sre-agent-${local.suffix}"
  resource_group_name = azurerm_resource_group.agent.name
  location            = var.location
  tags                = var.tags

  # ── Outbound: Azure service tags ──
  # Each rule is pinned at a low priority number so they remain effective
  # even if a broad deny-internet rule is added later.

  security_rule {
    name                       = "AllowAzureActiveDirectory"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureActiveDirectory"
  }

  security_rule {
    name                       = "AllowAzureResourceManager"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureResourceManager"
  }

  security_rule {
    name                       = "AllowAzureMonitor"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureMonitor"
  }

  security_rule {
    name                       = "AllowStorage"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Storage"
  }

  security_rule {
    name                       = "AllowAzureContainerRegistry"
    priority                   = 140
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureContainerRegistry"
  }

  security_rule {
    name                       = "AllowAzureKeyVault"
    priority                   = 150
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureKeyVault"
  }

  security_rule {
    name                       = "AllowAzureKubernetesService"
    priority                   = 160
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureKubernetesService"
  }

  # Catch-all for any other Azure service (Container Apps control plane,
  # Event Grid, Service Bus, etc.) not covered by a dedicated service tag above.
  security_rule {
    name                       = "AllowAzureCloud"
    priority                   = 170
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureCloud"
  }
}

resource "azurerm_subnet_network_security_group_association" "agent" {
  count                     = local.create_vnet ? 1 : 0
  subnet_id                 = azurerm_subnet.agent[0].id
  network_security_group_id = azurerm_network_security_group.agent[0].id
}

resource "azurerm_subnet" "agent" {
  count                = local.create_vnet ? 1 : 0
  name                 = "snet-sre-agent"
  resource_group_name  = azurerm_resource_group.agent.name
  virtual_network_name = azurerm_virtual_network.agent[0].name
  address_prefixes     = [var.agent_subnet_prefix]

  delegation {
    name = "Microsoft.App.environments"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}
