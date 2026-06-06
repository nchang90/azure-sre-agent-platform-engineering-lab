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

  depends_on = [
    azurerm_log_analytics_workspace.law
  ]

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

      scopes = [azurerm_log_analytics_workspace.law.id]

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

resource "azapi_resource" "orders_api_health" {
  count     = local.apps_enabled ? 1 : 0
  type      = "Microsoft.Insights/scheduledQueryRules@2022-06-15"
  name      = "alert-orders-api-health"
  location  = var.location
  parent_id = azurerm_resource_group.agent.id
  tags      = var.tags

  depends_on = [
    azurerm_log_analytics_workspace.law
  ]

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

      scopes = [azurerm_log_analytics_workspace.law.id]

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


resource "azurerm_monitor_smart_detector_alert_rule" "failure_anomalies" {
  name                = var.smart_detector_alert_rule_name != "" ? var.smart_detector_alert_rule_name : "failure anomalies - ${azurerm_application_insights.ai[0].name}"
  resource_group_name = azurerm_resource_group.agent.name
  severity            = var.severity_threshold[0]

  scope_resource_ids  = [azurerm_application_insights.ai[0].id]

  detector_type       = "FailureAnomaliesDetector"
  frequency           = "PT1M"
  enabled             = true

  action_group {
    ids = [azurerm_monitor_action_group.ai_smart_detection.id]
  }
}


resource "azurerm_monitor_action_group" "ai_smart_detection" {
  name                = "application-insights-smart-detection"
  resource_group_name = azurerm_resource_group.agent.name
  short_name          = "AISD"

  email_receiver {
    name          = "default"
    email_address = var.email_receiver_address
  }
}