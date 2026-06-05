locals {
  app_insights_resource_name = basename(var.app_insights_resource_id)
  log_analytics_resource_name = basename(var.law_resource_id)

  app_insights_connector = {
    name = "app-insights"
    properties = {
      dataConnectorType = "AppInsights"
      dataSource        = var.app_insights_resource_id
      extendedProperties = {
        armResourceId = var.app_insights_resource_id
        resource      = { name = local.app_insights_resource_name }
        appId         = var.app_insights_app_id
      }
      identity = "system"
    }
  }

  log_analytics_connector = {
    name = "log-analytics"
    properties = {
      dataConnectorType = "LogAnalytics"
      dataSource        = var.law_resource_id
      extendedProperties = {
        armResourceId = var.law_resource_id
        resource      = { name = local.log_analytics_resource_name }
      }
      identity = "system"
    }
  }

  azure_monitor_connector = {
    name = "azure-monitor"
    properties = {
      dataConnectorType = "AzureMonitor"
      dataSource        = data.azurerm_subscription.current.id
      extendedProperties = {
        armResourceId = data.azurerm_subscription.current.id
        lookbackDays  = var.azure_monitor_lookback_days
      }
      identity = "system"
    }
  }

  toggle_connectors = [
    for connector in [
      var.enable_app_insights_connector ? local.app_insights_connector : null,
      var.enable_log_analytics_connector ? local.log_analytics_connector : null,
      var.enable_azure_monitor_connector ? local.azure_monitor_connector : null,
    ] : connector if connector != null
  ]

  all_connectors = concat(local.toggle_connectors, var.connectors)
}

resource "azapi_resource" "connector" {
  for_each                  = { for c in local.all_connectors : c.name => c }
  schema_validation_enabled = false
  type                      = "Microsoft.App/agents/connectors@2025-05-01-preview"
  name                      = each.key
  parent_id                 = azapi_resource.sre_agent.id

  body = {
    properties = each.value.properties
  }

  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}
