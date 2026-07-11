locals {
  resolved_app_insights_id     = var.app_insights_resource_id != "" ? var.app_insights_resource_id : (local.create_app_insights ? azurerm_application_insights.ai[0].id : "")
  resolved_app_insights_app_id = var.app_insights_app_id != "" ? var.app_insights_app_id : (local.create_app_insights ? azurerm_application_insights.ai[0].app_id : "")
  resolved_law_id              = var.law_resource_id != "" ? var.law_resource_id : azurerm_log_analytics_workspace.law.id

  app_insights_resource_name  = basename(local.resolved_app_insights_id)
  log_analytics_resource_name = basename(local.resolved_law_id)

  app_insights_connector = {
    name = "app-insights"
    properties = {
      dataConnectorType = "AppInsights"
      dataSource        = local.resolved_app_insights_id
      extendedProperties = {
        armResourceId = local.resolved_app_insights_id
        resource      = { name = local.app_insights_resource_name }
        appId         = local.resolved_app_insights_app_id
      }
      identity = "system"
    }
  }

  log_analytics_connector = {
    name = "log-analytics"
    properties = {
      dataConnectorType = "LogAnalytics"
      dataSource        = local.resolved_law_id
      extendedProperties = {
        armResourceId = local.resolved_law_id
        resource      = { name = local.log_analytics_resource_name }
      }
      identity = "system"
    }
  }

  toggle_connectors = [
    for connector in [
      var.enable_app_insights_connector ? local.app_insights_connector : null,
      var.enable_log_analytics_connector ? local.log_analytics_connector : null,
    ] : connector if connector != null
  ]

  all_connectors = concat(local.toggle_connectors, var.connectors)

  # JSON-encode properties so the map values share one type (map(string)).
  # The connectors are heterogeneous, so without this the collection is typed
  # as a fixed object/tuple that cannot unify with the empty {} branch below.
  connector_map = { for c in local.all_connectors : c.name => jsonencode(c.properties) }
}

resource "azapi_resource" "connector" {
  for_each                  = var.deploy_sre_agent ? local.connector_map : {}
  schema_validation_enabled = false
  type                      = "Microsoft.App/agents/connectors@2025-05-01-preview"
  name                      = each.key
  parent_id                 = azapi_resource.sre_agent[0].id

  body = {
    properties = jsondecode(each.value)
  }

  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}
