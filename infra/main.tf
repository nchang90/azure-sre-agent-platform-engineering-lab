data "azurerm_subscription" "current" {}
data "azurerm_client_config" "current" {}

locals {
  suffix = substr(
    sha256("${data.azurerm_subscription.current.subscription_id}-${var.resource_group_name}-${var.agent_name}"),
    0,
    13,
  )

  # Identity selection: create new UAMI unless caller provides one.
  create_identity        = var.existing_managed_identity_id == ""
  effective_identity_id  = local.create_identity ? azurerm_user_assigned_identity.agent[0].id : var.existing_managed_identity_id
  effective_principal_id = local.create_identity ? azurerm_user_assigned_identity.agent[0].principal_id : data.azurerm_user_assigned_identity.existing[0].principal_id

  # App Insights selection: create new unless caller provides one.
  create_app_insights   = var.existing_agent_app_insights_id == ""
  effective_ai_app_id   = local.create_app_insights ? azurerm_application_insights.ai[0].app_id : data.azurerm_application_insights.existing_ai[0].app_id
  effective_ai_conn_str = local.create_app_insights ? azurerm_application_insights.ai[0].connection_string : data.azurerm_application_insights.existing_ai[0].connection_string

  sre_agent_admin_role_id = "e79298df-d852-4c6d-84f9-5d13249d1e55"
}

resource "azurerm_resource_group" "agent" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_user_assigned_identity" "agent" {
  count               = local.create_identity ? 1 : 0
  name                = "${var.agent_name}-id-${local.suffix}"
  resource_group_name = azurerm_resource_group.agent.name
  location            = var.location
  tags                = var.tags
}

data "azurerm_user_assigned_identity" "existing" {
  count               = local.create_identity ? 0 : 1
  name                = element(split("/", var.existing_managed_identity_id), length(split("/", var.existing_managed_identity_id)) - 1)
  resource_group_name = element(split("/", var.existing_managed_identity_id), 4)
}


resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${local.suffix}"
  resource_group_name = azurerm_resource_group.agent.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "ai" {
  count               = local.create_app_insights ? 1 : 0
  name                = "ai-${local.suffix}"
  resource_group_name = azurerm_resource_group.agent.name
  location            = var.location
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.law.id
  tags                = var.tags
}

data "azurerm_application_insights" "existing_ai" {
  count               = local.create_app_insights ? 0 : 1
  name                = element(split("/", var.existing_agent_app_insights_id), length(split("/", var.existing_agent_app_insights_id)) - 1)
  resource_group_name = element(split("/", var.existing_agent_app_insights_id), 4)
}


# Skills, subagents, tools, and common prompts are now deployed via data-plane
# (apply-extras.sh) instead of ARM to avoid tenant restrictions that block 3P tenants.

# ═══════════════════════════ RBAC ═════════════════════════════

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
  scope                = azurerm_resource_group.agent.id
  role_definition_name = "Reader"
  principal_id         = azapi_resource.sre_agent.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "self_smi_log_reader" {
  scope                = azurerm_resource_group.agent.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azapi_resource.sre_agent.identity[0].principal_id
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
  count                = var.access_level == "High" ? 1 : 0
  scope                = azurerm_resource_group.agent.id
  role_definition_name = "Contributor"
  principal_id         = azapi_resource.sre_agent.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# ── SRE Agent Administrator — deployer on the agent ──

resource "azurerm_role_assignment" "deployer_admin" {
  scope              = azapi_resource.sre_agent.id
  role_definition_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.sre_agent_admin_role_id}"
  principal_id       = data.azurerm_client_config.current.object_id
}

# ── SRE Agent Administrator — UAMI on the agent ──

resource "azurerm_role_assignment" "uami_admin" {
  scope              = azapi_resource.sre_agent.id
  role_definition_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.sre_agent_admin_role_id}"
  principal_id       = local.effective_principal_id
  principal_type     = "ServicePrincipal"
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

# ═══════════ System MI RBAC on target RGs ═════════════
# The agent uses system-assigned MI for connector queries (App Insights, Log Analytics).
# Same roles as UAMI: Reader + Log Analytics Reader + Contributor (if High).

resource "azurerm_role_assignment" "smi_target_reader" {
  for_each             = toset(var.target_resource_groups)
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${each.value}"
  role_definition_name = "Reader"
  principal_id         = azapi_resource.sre_agent.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "smi_target_log_reader" {
  for_each             = toset(var.target_resource_groups)
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${each.value}"
  role_definition_name = "Log Analytics Reader"
  principal_id         = azapi_resource.sre_agent.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "smi_target_contributor" {
  for_each             = var.access_level == "High" ? toset(var.target_resource_groups) : toset([])
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${each.value}"
  role_definition_name = "Contributor"
  principal_id         = azapi_resource.sre_agent.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}