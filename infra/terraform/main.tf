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
  name                = regex("[^/]+$", var.existing_managed_identity_id)
  resource_group_name = regex("/resourceGroups/([^/]+)/", var.existing_managed_identity_id)[0]
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
  name                = regex("[^/]+$", var.existing_agent_app_insights_id)
  resource_group_name = regex("/resourceGroups/([^/]+)/", var.existing_agent_app_insights_id)[0]
}

# Role assignments live in rbac.tf.