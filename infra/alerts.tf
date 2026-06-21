resource "azurerm_monitor_action_group" "sre_lab" {
  count               = local.apps_enabled ? 1 : 0
  name                = "ag-sre-lab-${local.suffix}"
  resource_group_name = azurerm_resource_group.agent.name
  short_name          = "sreLab"
  tags                = var.tags
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "orders_api_health" {
  count               = local.apps_enabled ? 1 : 0
  name                = "alert-orders-api-health"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  tags                = var.tags
  depends_on          = [azurerm_log_analytics_workspace.law]

  description             = "Orders API: /health endpoint unhealthy or missing in the last 5 minutes."
  display_name            = "Orders API health check failing"
  severity                = 1
  enabled                 = true
  evaluation_frequency    = "PT5M"
  window_duration         = "PT5M"
  auto_mitigation_enabled = true
  skip_query_validation   = true
  scopes                  = [azurerm_log_analytics_workspace.law.id]

  criteria {
    query = <<-KQL
      ContainerAppSystemLogs_CL
      | where ContainerAppName_s == "orders-api"
      | where Log_s has_any ("ProbeFailure", "Liveness probe failed", "Readiness probe failed", "container restarted")
      | summarize ProbeFailures = count()
    KQL

    operator                = "GreaterThan"
    threshold               = 0
    time_aggregation_method = "Count"
  }

  action {
    action_groups = [azurerm_monitor_action_group.sre_lab[0].id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "orders_api_errors" {
  count               = local.apps_enabled ? 1 : 0
  name                = "alert-orders-api-errors"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  tags                = var.tags
  depends_on          = [azurerm_log_analytics_workspace.law]

  description             = "Orders API: 5xx responses detected in the last 5 minutes."
  display_name            = "Orders API 5xx spike"
  severity                = 2
  enabled                 = true
  evaluation_frequency    = "PT1M"
  window_duration         = "PT5M"
  auto_mitigation_enabled = true
  skip_query_validation   = true
  scopes                  = [azurerm_log_analytics_workspace.law.id]

  criteria {
    query = <<-KQL
      AppRequests
      | where TimeGenerated > ago(5m)
      | where tostring(AppRoleName) == "orders-api" or tostring(Url) has "orders-api"
      | where tostring(ResultCode) startswith "5"
      | summarize FailedRequests = count()
    KQL

    operator                = "GreaterThan"
    threshold               = 5
    time_aggregation_method = "Count"
  }

  action {
    action_groups = [azurerm_monitor_action_group.sre_lab[0].id]
  }
}


resource "azurerm_monitor_smart_detector_alert_rule" "failure_anomalies" {
  count               = local.create_app_insights ? 1 : 0
  name                = "failure-anomalies-ai-51a0c59340d39-sev2"
  resource_group_name = azurerm_resource_group.agent.name
  severity            = var.severity_threshold
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

