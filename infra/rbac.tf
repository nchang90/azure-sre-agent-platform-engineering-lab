# Role assignments for the agent's user-assigned identity (UAMI) and the agent's
# system-assigned identity (SMI). Split out of main.tf for readability; Terraform
# loads all *.tf in this directory together, so this is purely organizational.

# ── Monitoring Reader on agent RG ──

resource "azurerm_role_assignment" "monitoring_reader" {
  scope                = azurerm_resource_group.agent.id
  role_definition_name = "Monitoring Reader"
  principal_id         = local.effective_principal_id
  principal_type       = "ServicePrincipal"
}

# Agent RG always needs Log Analytics Reader for the UAMI (so the agent can
# query its own LAW / App Insights regardless of var.target_resource_groups).
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

# ── Agent RG: Contributor (High access only) ──
# Lets the agent remediate its own workload (e.g. roll back orders-api) when
# running in High / Automatic mode. Off by default (access_level = "Low").

resource "azurerm_role_assignment" "self_contributor" {
  count                = var.access_level == "High" ? 1 : 0
  scope                = azurerm_resource_group.agent.id
  role_definition_name = "Contributor"
  principal_id         = local.effective_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "self_smi_contributor" {
  count                = var.deploy_sre_agent && var.access_level == "High" ? 1 : 0
  scope                = azurerm_resource_group.agent.id
  role_definition_name = "Contributor"
  principal_id         = azapi_resource.sre_agent[0].identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# ── Subscription: Monitoring Contributor ──

resource "azurerm_role_assignment" "monitoring_contributor_uami" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Monitoring Contributor"
  principal_id         = local.effective_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "monitoring_contributor_smi" {
  count                = var.deploy_sre_agent ? 1 : 0
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Monitoring Contributor"
  principal_id         = azapi_resource.sre_agent[0].identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# ── Subscription: Container Apps Contributor ──

resource "azurerm_role_assignment" "container_apps_contributor_uami" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Container Apps Contributor"
  principal_id         = local.effective_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "container_apps_contributor_smi" {
  count                = var.deploy_sre_agent ? 1 : 0
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Container Apps Contributor"
  principal_id         = azapi_resource.sre_agent[0].identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# ── SRE Agent Administrator — deployer on the agent ──

resource "azurerm_role_assignment" "deployer_admin" {
  count              = var.deploy_sre_agent ? 1 : 0
  scope              = azapi_resource.sre_agent[0].id
  role_definition_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.sre_agent_admin_role_id}"
  principal_id       = data.azurerm_client_config.current.object_id
}

# ── SRE Agent Administrator — UAMI on the agent ──

resource "azurerm_role_assignment" "uami_admin" {
  count              = var.deploy_sre_agent ? 1 : 0
  scope              = azapi_resource.sre_agent[0].id
  role_definition_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.sre_agent_admin_role_id}"
  principal_id       = local.effective_principal_id
  principal_type     = "ServicePrincipal"
}

# ── SRE Agent Administrator — additional admin principals ──

resource "azurerm_role_assignment" "admin_principals" {
  for_each           = var.deploy_sre_agent ? toset(var.admin_principal_ids) : toset([])
  scope              = azapi_resource.sre_agent[0].id
  role_definition_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.sre_agent_admin_role_id}"
  principal_id       = each.value
}

# ── Target RG: Reader ──

resource "azurerm_role_assignment" "target_reader" {
  for_each             = toset(var.target_resource_groups)
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${each.value}"
  role_definition_name = "Reader"
  principal_id         = local.effective_principal_id
  principal_type       = "ServicePrincipal"
}

# ── Target RG: Log Analytics Reader ──

resource "azurerm_role_assignment" "target_log_reader" {
  for_each             = toset(var.target_resource_groups)
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${each.value}"
  role_definition_name = "Log Analytics Reader"
  principal_id         = local.effective_principal_id
  principal_type       = "ServicePrincipal"
}

# ── Target RG: Contributor (High access only) ──

resource "azurerm_role_assignment" "target_contributor" {
  for_each             = var.access_level == "High" ? toset(var.target_resource_groups) : toset([])
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${each.value}"
  role_definition_name = "Contributor"
  principal_id         = local.effective_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "smi_target_reader" {
  for_each             = var.deploy_sre_agent ? toset(var.target_resource_groups) : toset([])
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${each.value}"
  role_definition_name = "Reader"
  principal_id         = azapi_resource.sre_agent[0].identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "smi_target_log_reader" {
  for_each             = var.deploy_sre_agent ? toset(var.target_resource_groups) : toset([])
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${each.value}"
  role_definition_name = "Log Analytics Reader"
  principal_id         = azapi_resource.sre_agent[0].identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "smi_target_contributor" {
  for_each             = var.deploy_sre_agent && var.access_level == "High" ? toset(var.target_resource_groups) : toset([])
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${each.value}"
  role_definition_name = "Contributor"
  principal_id         = azapi_resource.sre_agent[0].identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
