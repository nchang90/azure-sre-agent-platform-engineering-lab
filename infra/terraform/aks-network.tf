resource "azurerm_virtual_network" "aks" {
  name                = "vnet-aks-${local.aks_suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  address_space       = [var.aks_vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.agent.name
  virtual_network_name = azurerm_virtual_network.aks.name
  address_prefixes     = [var.aks_subnet_cidr]

  # AKS node pool subnets must not be delegated; AKS needs to manage the
  # subnet directly for the agent pool network plugin configuration.
}

resource "azurerm_user_assigned_identity" "aks" {
  name                = "aks-${local.aks_suffix}-uami"
  resource_group_name = azurerm_resource_group.agent.name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = azurerm_subnet.aks.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "aks_vnet_network_contributor" {
  scope                = azurerm_virtual_network.aks.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
  principal_type       = "ServicePrincipal"
}
