data "azurerm_subscription" "current" {}
data "azurerm_client_config" "current" {}

locals {
  suffix = substr(
    sha256("${data.azurerm_subscription.current.subscription_id}-${var.resource_group_name}-${var.agent_name}"),
    0,
    13,
  )

  create_identity        = var.existing_managed_identity_id == ""
  effective_identity_id  = local.create_identity ? azurerm_user_assigned_identity.agent[0].id : var.existing_managed_identity_id
  effective_principal_id = local.create_identity ? azurerm_user_assigned_identity.agent[0].principal_id : data.azurerm_user_assigned_identity.existing[0].principal_id

  create_app_insights   = var.existing_agent_app_insights_id == ""
  effective_ai_id       = local.create_app_insights ? azapi_resource.ai[0].id : data.azurerm_application_insights.existing_ai[0].id
  effective_ai_app_id   = local.create_app_insights ? azapi_resource.ai[0].output.properties.AppId : data.azurerm_application_insights.existing_ai[0].app_id
  effective_ai_conn_str = local.create_app_insights ? azapi_resource.ai[0].output.properties.ConnectionString : data.azurerm_application_insights.existing_ai[0].connection_string

  sre_agent_standard_user_role_id = "2d84a65a-63b2-4343-bbb6-31105d857bc1"
  sre_agent_admin_role_id         = "e79298df-d852-4c6d-84f9-5d13249d1e55"

  scenario_value = lower(trimspace(var.scenario))

  apps_enabled    = local.scenario_value == "s1" || (local.scenario_value == "s2" && var.runtime == "containerapps")
  webapps_enabled = local.scenario_value == "s4" || (local.scenario_value == "s2" && var.runtime == "webapp")
  aks_enabled     = local.scenario_value == "s3"
  images_enabled  = local.apps_enabled || local.webapps_enabled
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

resource "azapi_resource" "ai" {
  count                     = local.create_app_insights ? 1 : 0
  schema_validation_enabled = false
  type                      = "Microsoft.Insights/components@2020-02-02"
  name                      = "ai-${local.suffix}"
  location                  = var.location
  parent_id                 = azurerm_resource_group.agent.id
  tags                      = var.tags

  response_export_values = [
    "properties.AppId",
    "properties.ConnectionString",
  ]

  body = {
    kind = "web"
    properties = {
      Application_Type    = "web"
      Request_Source      = "SreAgent"
      WorkspaceResourceId = azurerm_log_analytics_workspace.law.id
    }
  }
}

data "azurerm_application_insights" "existing_ai" {
  count               = local.create_app_insights ? 0 : 1
  name                = regex("[^/]+$", var.existing_agent_app_insights_id)
  resource_group_name = regex("/resourceGroups/([^/]+)/", var.existing_agent_app_insights_id)[0]
}
