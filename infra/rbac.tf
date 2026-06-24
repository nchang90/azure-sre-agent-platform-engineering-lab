resource "azurerm_role_assignment" "monitoring_reader" {
  scope                = azurerm_resource_group.agent.id
  role_definition_name = "Monitoring Reader"
  principal_id         = local.effective_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "self_log_reader" {
  scope                = azurerm_resource_group.agent.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = local.effective_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "self_smi_reader" {
  count                = var.deploy_sre_agent ? 1 : 0
  scope                = azurerm_resource_group.agent.id
  role_definition_name = "Reader"
  principal_id         = azapi_resource.sre_agent[0].identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "self_smi_log_reader" {
  count                = var.deploy_sre_agent ? 1 : 0
  scope                = azurerm_resource_group.agent.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azapi_resource.sre_agent[0].identity[0].principal_id
  principal_type       = "ServicePrincipal"
}


resource "azurerm_role_assignment" "deployer_admin" {
  count              = var.deploy_sre_agent ? 1 : 0
  scope              = azapi_resource.sre_agent[0].id
  role_definition_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.sre_agent_admin_role_id}"
  principal_id       = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "deployer_monitoring_contributor_rg" {
  scope                = azurerm_resource_group.agent.id
  role_definition_name = "Monitoring Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "deployer_log_analytics_reader_rg" {
  scope                = azurerm_resource_group.agent.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "uami_admin" {
  count              = var.deploy_sre_agent ? 1 : 0
  scope              = azapi_resource.sre_agent[0].id
  role_definition_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.sre_agent_admin_role_id}"
  principal_id       = local.effective_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "admin_principals" {
  for_each           = var.deploy_sre_agent ? toset(var.admin_principal_ids) : toset([])
  scope              = azapi_resource.sre_agent[0].id
  role_definition_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.sre_agent_admin_role_id}"
  principal_id       = each.value
}

