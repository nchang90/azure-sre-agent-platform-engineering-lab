resource "azurerm_monitor_action_group" "sre_lab" {
  count               = local.apps_enabled ? 1 : 0
  name                = "ag-sre-lab-${local.suffix}"
  resource_group_name = azurerm_resource_group.agent.name
  short_name          = "sreLab"
  tags                = var.tags

  dynamic "webhook_receiver" {
    for_each = var.webhook_bridge_trigger_url == "" ? [] : [var.webhook_bridge_trigger_url]

    content {
      name                    = "sre-agent-hook"
      service_uri             = webhook_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "orders_api_health" {
  count               = local.apps_enabled ? 1 : 0
  name                = "alert-orders-api-health"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  tags                = var.tags
  depends_on = [
    azurerm_log_analytics_workspace.law,
  ]

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
      let SystemLogs = union isfuzzy=true
        (ContainerAppSystemLogs_CL
          | project
              TimeGenerated,
              ContainerAppName = tostring(column_ifexists("ContainerAppName_s", "")),
              Reason = tostring(column_ifexists("Reason_s", "")),
              Log = tostring(column_ifexists("Log_s", ""))),
        (datatable(TimeGenerated:datetime, ContainerAppName:string, Reason:string, Log:string)[]);
      SystemLogs
      | where TimeGenerated > ago(5m)
      | where ContainerAppName == "orders-api"
      | where Reason == "ReplicaUnhealthy" or Log has "probe failed"
      | summarize ProbeFailures = count()
      | extend ProbeFailures = coalesce(ProbeFailures, 0)
    KQL

    operator                = "GreaterThan"
    threshold               = 0
    time_aggregation_method = "Maximum"
    metric_measure_column   = "ProbeFailures"
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
  depends_on = [
    azurerm_log_analytics_workspace.law,
  ]

  description             = "Orders API: container errors / back-off (crash loop) detected in the last 5 minutes."
  display_name            = "Orders API container errors"
  severity                = 2
  enabled                 = true
  evaluation_frequency    = "PT5M"
  window_duration         = "PT5M"
  auto_mitigation_enabled = true
  skip_query_validation   = true
  scopes                  = [azurerm_log_analytics_workspace.law.id]

  criteria {
    query = <<-KQL
      let SystemLogs = union isfuzzy=true
        (ContainerAppSystemLogs_CL
          | project
              TimeGenerated,
              ContainerAppName = tostring(column_ifexists("ContainerAppName_s", "")),
              Reason = tostring(column_ifexists("Reason_s", "")),
              Log = tostring(column_ifexists("Log_s", ""))),
        (datatable(TimeGenerated:datetime, ContainerAppName:string, Reason:string, Log:string)[]);
      SystemLogs
      | where TimeGenerated > ago(5m)
      | where ContainerAppName == "orders-api"
      | where Reason in ("ContainerBackOff", "Completed", "BackOff") or Log has_any ("back-off", "crash", "error", "terminated")
      | summarize FailedEvents = count()
      | extend FailedEvents = coalesce(FailedEvents, 0)
    KQL

    operator                = "GreaterThan"
    threshold               = 0
    time_aggregation_method = "Maximum"
    metric_measure_column   = "FailedEvents"
  }

  action {
    action_groups = [azurerm_monitor_action_group.sre_lab[0].id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "orders_api_latency" {
  count               = local.apps_enabled ? 1 : 0
  name                = "alert-orders-api-latency"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  tags                = var.tags
  depends_on = [
    azurerm_log_analytics_workspace.law,
  ]

  description             = "Orders API: P99 request latency exceeded the 2s SLO over the last 1 minute."
  display_name            = "Orders API latency (P99) degraded"
  severity                = 2
  enabled                 = true
  evaluation_frequency    = "PT1M"
  window_duration         = "PT1M"
  auto_mitigation_enabled = true
  skip_query_validation   = true
  scopes                  = [azurerm_log_analytics_workspace.law.id]

  criteria {
    query = <<-KQL
      AppRequests
      | where AppRoleName == "orders-api"
      | summarize P99Ms = percentile(DurationMs, 99) by bin(TimeGenerated, 1m)
    KQL

    operator                = "GreaterThan"
    threshold               = 2000
    time_aggregation_method = "Maximum"
    metric_measure_column   = "P99Ms"
  }

  action {
    action_groups = [azurerm_monitor_action_group.sre_lab[0].id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "aks_pod_crashloop" {
  count               = local.aks_enabled ? 1 : 0
  name                = "alert-aks-pod-crashloop"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  tags                = var.tags
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_log_analytics_workspace.law,
  ]

  description             = "AKS: pods are crash looping or backing off."
  display_name            = "AKS pod crash loop detected"
  severity                = 1
  enabled                 = true
  evaluation_frequency    = "PT5M"
  window_duration         = "PT5M"
  auto_mitigation_enabled = true
  skip_query_validation   = true
  scopes                  = [azurerm_log_analytics_workspace.law.id]

  criteria {
    query = <<-KQL
      let Pods = union isfuzzy=true
        (KubePodInventory
          | project TimeGenerated, ClusterName = tostring(column_ifexists("ClusterName", "")), Name = tostring(column_ifexists("Name", "")), ContainerStatusReason = tostring(column_ifexists("ContainerStatusReason", ""))),
        (datatable(TimeGenerated:datetime, ClusterName:string, Name:string, ContainerStatusReason:string)[]);
      Pods
      | where TimeGenerated > ago(5m)
      | where ClusterName startswith "aks-"
      | where ContainerStatusReason in ("CrashLoopBackOff", "Error", "ContainerCannotRun", "ImagePullBackOff", "ErrImagePull")
      | summarize AffectedPods = dcount(Name)
    KQL

    operator                = "GreaterThan"
    threshold               = 0
    time_aggregation_method = "Maximum"
    metric_measure_column   = "AffectedPods"
  }

  action {
    action_groups = [azurerm_monitor_action_group.ai_smart_detection.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "aks_pods_not_ready" {
  count               = local.aks_enabled ? 1 : 0
  name                = "alert-aks-pods-not-ready"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  tags                = var.tags
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_log_analytics_workspace.law,
  ]

  description             = "AKS: one or more pods are not ready."
  display_name            = "AKS pods not ready"
  severity                = 2
  enabled                 = true
  evaluation_frequency    = "PT5M"
  window_duration         = "PT5M"
  auto_mitigation_enabled = true
  skip_query_validation   = true
  scopes                  = [azurerm_log_analytics_workspace.law.id]

  criteria {
    query = <<-KQL
      let Pods = union isfuzzy=true
        (KubePodInventory
          | project TimeGenerated, ClusterName = tostring(column_ifexists("ClusterName", "")), Name = tostring(column_ifexists("Name", "")), PodStatus = tostring(column_ifexists("PodStatus", "")), ContainerReady = tostring(column_ifexists("ContainerReady", ""))),
        (datatable(TimeGenerated:datetime, ClusterName:string, Name:string, PodStatus:string, ContainerReady:string)[]);
      Pods
      | where TimeGenerated > ago(5m)
      | where ClusterName startswith "aks-"
      | where PodStatus !in ("Running", "Succeeded") or tolower(ContainerReady) == "false"
      | summarize AffectedPods = dcount(Name)
    KQL

    operator                = "GreaterThan"
    threshold               = 0
    time_aggregation_method = "Maximum"
    metric_measure_column   = "AffectedPods"
  }

  action {
    action_groups = [azurerm_monitor_action_group.ai_smart_detection.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "aks_node_cpu_pressure" {
  count               = local.aks_enabled ? 1 : 0
  name                = "alert-aks-node-cpu-pressure"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  tags                = var.tags
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_log_analytics_workspace.law,
  ]

  description             = "AKS: node CPU usage is above 85%."
  display_name            = "AKS node CPU pressure"
  severity                = 2
  enabled                 = true
  evaluation_frequency    = "PT5M"
  window_duration         = "PT5M"
  auto_mitigation_enabled = true
  skip_query_validation   = true
  scopes                  = [azurerm_log_analytics_workspace.law.id]

  criteria {
    query = <<-KQL
      let Metrics = union isfuzzy=true
        (InsightsMetrics
          | project TimeGenerated, Namespace = tostring(column_ifexists("Namespace", "")), Name = tostring(column_ifexists("Name", "")), Val = todouble(column_ifexists("Val", 0.0))),
        (datatable(TimeGenerated:datetime, Namespace:string, Name:string, Val:real)[]);
      Metrics
      | where TimeGenerated > ago(5m)
      | where Namespace == "container.azm.ms/insights"
      | where Name == "cpuUsagePercentage"
      | summarize MaxCpu = max(Val)
      | extend MaxCpu = coalesce(MaxCpu, 0.0)
    KQL

    operator                = "GreaterThan"
    threshold               = 85
    time_aggregation_method = "Maximum"
    metric_measure_column   = "MaxCpu"
  }

  action {
    action_groups = [azurerm_monitor_action_group.ai_smart_detection.id]
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
