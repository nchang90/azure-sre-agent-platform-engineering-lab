resource "azurerm_virtual_network" "aks" {
  count               = local.aks_enabled ? 1 : 0
  name                = "vnet-aks-${local.aks_suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  address_space       = [var.aks_vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  count                = local.aks_enabled ? 1 : 0
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.agent.name
  virtual_network_name = azurerm_virtual_network.aks[0].name
  address_prefixes     = [var.aks_subnet_cidr]
}

resource "azurerm_user_assigned_identity" "aks" {
  count               = local.aks_enabled ? 1 : 0
  name                = "aks-${local.aks_suffix}-uami"
  resource_group_name = azurerm_resource_group.agent.name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "aks_network_contributor" {
  count                = local.aks_enabled ? 1 : 0
  scope                = azurerm_subnet.aks[0].id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "aks_vnet_network_contributor" {
  count                = local.aks_enabled ? 1 : 0
  scope                = azurerm_virtual_network.aks[0].id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks[0].principal_id
  principal_type       = "ServicePrincipal"
}
