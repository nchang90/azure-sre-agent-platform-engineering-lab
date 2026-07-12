resource "azurerm_monitor_action_group" "sre_lab" {
  count               = local.apps_enabled ? 1 : 0
  name                = "ag-sre-lab-${local.suffix}"
  resource_group_name = azurerm_resource_group.agent.name
  short_name          = "sreLab"
  tags                = var.tags
}

resource "azapi_resource" "orders_api_5xx" {
  count     = local.apps_enabled ? 1 : 0
  type      = "Microsoft.Insights/scheduledQueryRules@2022-06-15"
  name      = "alert-orders-api-5xx"
  location  = var.location
  parent_id = azurerm_resource_group.agent.id
  tags      = var.tags

  body = {
    properties = {
      description         = "Orders API: spike in 5xx responses or error logs over the last 5 minutes."
      displayName         = "Orders API 5xx"
      severity            = 2
      enabled             = true
      evaluationFrequency = "PT5M"
      windowSize          = "PT5M"
      autoMitigate        = true
      skipQueryValidation = true
      scopes              = [azurerm_log_analytics_workspace.law.id]
      criteria = {
        allOf = [{
          query           = "ContainerAppConsoleLogs_CL\n| where ContainerAppName_s == \"orders-api\"\n| where Log_s contains \"500\" or Log_s contains \"error\" or Log_s contains \"failed\"\n| summarize ErrorCount = count()"
          operator        = "GreaterThan"
          threshold       = 5
          timeAggregation = "Count"
        }]
      }
      actions = {
        actionGroups = [azurerm_monitor_action_group.sre_lab[0].id]
      }
    }
  }
}

# Availability alert: orders-api health endpoint failing.
resource "azapi_resource" "orders_api_health" {
  count     = local.apps_enabled ? 1 : 0
  type      = "Microsoft.Insights/scheduledQueryRules@2022-06-15"
  name      = "alert-orders-api-health"
  location  = var.location
  parent_id = azurerm_resource_group.agent.id
  tags      = var.tags

  body = {
    properties = {
      description         = "Orders API: /health endpoint unhealthy or missing in the last 5 minutes."
      displayName         = "Orders API health check failing"
      severity            = 1
      enabled             = true
      evaluationFrequency = "PT5M"
      windowSize          = "PT5M"
      autoMitigate        = true
      skipQueryValidation = true
      scopes              = [azurerm_log_analytics_workspace.law.id]
      criteria = {
        allOf = [{
          query           = "ContainerAppSystemLogs_CL\n| where ContainerAppName_s == \"orders-api\"\n| where Log_s has_any (\"ProbeFailure\", \"Liveness probe failed\", \"Readiness probe failed\", \"container restarted\")\n| summarize ProbeFailures = count()"
          operator        = "GreaterThan"
          threshold       = 0
          timeAggregation = "Count"
        }]
      }
      actions = {
        actionGroups = [azurerm_monitor_action_group.sre_lab[0].id]
      }
    }
  }
}
