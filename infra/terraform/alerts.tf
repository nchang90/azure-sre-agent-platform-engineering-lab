resource "azurerm_monitor_action_group" "sre_lab" {
  count               = local.apps_enabled || local.webapps_enabled ? 1 : 0
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

  description             = "Orders API: /health endpoint unhealthy or missing in the last 1 minute."
  display_name            = "Orders API health check failing"
  severity                = 1
  enabled                 = true
  evaluation_frequency    = "PT1M"
  window_duration         = "PT1M"
  auto_mitigation_enabled = true
  skip_query_validation   = true
  scopes                  = [azurerm_log_analytics_workspace.law.id]

  criteria {
    query = <<-KQL
      ContainerAppSystemLogs_CL
      | where ContainerAppName_s == "orders-api"
      | where Reason_s == "ReplicaUnhealthy" or Log_s has "probe failed"
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
  depends_on = [
    azurerm_log_analytics_workspace.law,
    azurerm_monitor_scheduled_query_rules_alert_v2.orders_api_health,
  ]

  description             = "Orders API: container errors / back-off (crash loop) detected in the last 1 minute."
  display_name            = "Orders API container errors"
  severity                = 2
  enabled                 = true
  evaluation_frequency    = "PT1M"
  window_duration         = "PT1M"
  auto_mitigation_enabled = true
  skip_query_validation   = true
  scopes                  = [azurerm_log_analytics_workspace.law.id]

  criteria {
    query = <<-KQL
      ContainerAppSystemLogs_CL
      | where ContainerAppName_s == "orders-api"
      | where Reason_s in ("ContainerBackOff", "Completed", "BackOff") or Log_s has_any ("back-off", "crash", "error", "terminated")
      | summarize FailedEvents = count()
    KQL

    operator                = "GreaterThan"
    threshold               = 0
    time_aggregation_method = "Count"
  }

  action {
    action_groups = [azurerm_monitor_action_group.sre_lab[0].id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "orders_api_5xx" {
  count               = local.apps_enabled || local.webapps_enabled ? 1 : 0
  name                = "alert-orders-api-5xx"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  tags                = var.tags
  depends_on = [
    azapi_resource.ai,
    azurerm_monitor_scheduled_query_rules_alert_v2.orders_api_errors,
  ]

  description             = "Orders API: more than five HTTP 5xx responses detected in the last five minutes."
  display_name            = "Orders API HTTP 5xx spike"
  severity                = 1
  enabled                 = true
  evaluation_frequency    = "PT5M"
  window_duration         = "PT5M"
  auto_mitigation_enabled = true
  skip_query_validation   = true
  scopes                  = [local.effective_ai_id]

  criteria {
    query = <<-KQL
      requests
      | where cloud_RoleName == "orders-api"
      | where success == false and resultCode startswith "5"
      | summarize FailedRequests = count()
    KQL

    operator                = "GreaterThan"
    threshold               = 5
    time_aggregation_method = "Maximum"
    metric_measure_column   = "FailedRequests"
  }

  action {
    action_groups = [azurerm_monitor_action_group.sre_lab[0].id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "orders_api_latency" {
  count               = local.apps_enabled || (local.scenario_value == "s2" && local.webapps_enabled) ? 1 : 0
  name                = "alert-orders-api-latency"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  tags                = var.tags
  depends_on = [
    azapi_resource.ai,
    azurerm_log_analytics_workspace.law,
    azurerm_monitor_scheduled_query_rules_alert_v2.orders_api_5xx,
  ]

  description             = "Orders API: P99 request latency exceeded the 2s SLO over the last 5 minutes."
  display_name            = "Orders API latency (P99) degraded"
  severity                = 2
  enabled                 = true
  evaluation_frequency    = "PT5M"
  window_duration         = "PT5M"
  auto_mitigation_enabled = true
  skip_query_validation   = true
  scopes                  = [local.effective_ai_id]

  criteria {
    query = <<-KQL
      requests
      | extend AppName = tostring(column_ifexists("cloud_RoleName", column_ifexists("AppRoleName", "")))
      | where AppName == "orders-api"
      | summarize P99Ms = percentile(duration, 99) by bin(timestamp, 1m)
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

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "aks_crashloop_oom" {
  count               = local.aks_enabled ? 1 : 0
  name                = "alert-aks-crashloop-oom"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  tags                = var.tags
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_log_analytics_workspace.law,
  ]

  description             = "AKS: a container in any namespace reports CrashLoopBackOff, OOMKilled, image-pull, or startup errors."
  display_name            = "AKS - CrashLoop/OOM detected"
  severity                = 1
  enabled                 = true
  evaluation_frequency    = "PT1M"
  window_duration         = "PT5M"
  auto_mitigation_enabled = true
  skip_query_validation   = true
  scopes                  = [azurerm_log_analytics_workspace.law.id]

  criteria {
    query = <<-KQL
      KubePodInventory
      | where TimeGenerated > ago(2m)
      | where ClusterName startswith "aks-"
      | summarize arg_max(TimeGenerated, *) by ContainerName
      | where ContainerStatusReason in~ ("CrashLoopBackOff", "OOMKilled", "Error", "ImagePullBackOff", "ErrImagePull", "CreateContainerConfigError", "ContainerCannotRun")
    KQL

    operator                = "GreaterThan"
    threshold               = 0
    time_aggregation_method = "Count"
  }

  action {
    action_groups = [azurerm_monitor_action_group.ai_smart_detection.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "aks_orders_api_unavailable" {
  count               = local.aks_enabled ? 1 : 0
  name                = "alert-aks-orders-api-unavailable"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  tags                = var.tags
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_log_analytics_workspace.law,
  ]

  description             = "AKS: the critical orders-api workload has no running healthy pods."
  display_name            = "AKS orders-api workload unavailable"
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
          | project TimeGenerated, ClusterName = tostring(column_ifexists("ClusterName", "")), Namespace = tostring(column_ifexists("Namespace", "")), Name = tostring(column_ifexists("Name", "")), ContainerName = tostring(column_ifexists("ContainerName", "")), PodStatus = tostring(column_ifexists("PodStatus", "")), ContainerStatus = tostring(column_ifexists("ContainerStatus", "")), ContainerStatusReason = tostring(column_ifexists("ContainerStatusReason", "")), PodRestartCount = tolong(column_ifexists("PodRestartCount", 0)), PodLabel = tostring(column_ifexists("PodLabel", ""))),
        (datatable(TimeGenerated:datetime, ClusterName:string, Namespace:string, Name:string, ContainerName:string, PodStatus:string, ContainerStatus:string, ContainerStatusReason:string, PodRestartCount:long, PodLabel:string)[]);
      let Events = union isfuzzy=true
        (KubeEvents
          | project TimeGenerated, ClusterName = tostring(column_ifexists("ClusterName", "")), Name = tostring(column_ifexists("Name", "")), Reason = tostring(column_ifexists("Reason", "")), Message = tostring(column_ifexists("Message", ""))),
        (datatable(TimeGenerated:datetime, ClusterName:string, Name:string, Reason:string, Message:string)[]);
      let ClusterPods = Pods
        | where TimeGenerated > ago(5m)
        | where ClusterName startswith "aks-";
      let LatestBatch = toscalar(ClusterPods | summarize max(TimeGenerated));
      let ProbeFailing = Events
        | where TimeGenerated > ago(3m)
        | where ClusterName startswith "aks-" and Name startswith "orders-api-"
        | where Reason == "Unhealthy" and Message has "Readiness probe failed"
        | distinct Name;
      ClusterPods
      | where Name startswith "orders-api-"
      | summarize arg_max(TimeGenerated, PodStatus, ContainerStatus, ContainerStatusReason) by Namespace, Name, ContainerName
      | where TimeGenerated >= LatestBatch - 30s
      | summarize UnhealthyContainers = countif(not(PodStatus == "Running" and ((ContainerStatus == "running" and isempty(ContainerStatusReason)) or (ContainerStatus == "terminated" and ContainerStatusReason == "Completed")))) by Namespace, Name
      | where UnhealthyContainers == 0
      | where Name !in (ProbeFailing)
      | summarize ReadyPods = count()
    KQL

    operator                = "LessThan"
    threshold               = 1
    time_aggregation_method = "Maximum"
    metric_measure_column   = "ReadyPods"
  }

  action {
    action_groups = [azurerm_monitor_action_group.ai_smart_detection.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "aks_orders_api_service_missing" {
  count               = local.aks_enabled ? 1 : 0
  name                = "alert-aks-orders-api-service-missing"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  tags                = var.tags
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_log_analytics_workspace.law,
  ]

  description             = "AKS: the critical orders-api Kubernetes service is missing from the cluster."
  display_name            = "AKS orders-api service missing"
  severity                = 1
  enabled                 = true
  evaluation_frequency    = "PT5M"
  window_duration         = "PT5M"
  auto_mitigation_enabled = true
  skip_query_validation   = true
  scopes                  = [azurerm_log_analytics_workspace.law.id]

  criteria {
    query = <<-KQL
      let Services = union isfuzzy=true
        (KubeServices
          | project TimeGenerated, ClusterName = tostring(column_ifexists("ClusterName", "")), Namespace = tostring(column_ifexists("Namespace", "")), ServiceName = tostring(column_ifexists("ServiceName", column_ifexists("Name", ""))), SelectorLabels = tostring(column_ifexists("SelectorLabels", ""))),
        (datatable(TimeGenerated:datetime, ClusterName:string, Namespace:string, ServiceName:string, SelectorLabels:string)[]);
      let ClusterServices = Services
        | where TimeGenerated > ago(5m)
        | where ClusterName startswith "aks-";
      let LatestBatch = toscalar(ClusterServices | summarize max(TimeGenerated));
      ClusterServices
      | where TimeGenerated >= LatestBatch - 30s
      | where ServiceName == "orders-api"
      | summarize MatchingServices = count()
      | extend MatchingServices = coalesce(MatchingServices, 0)
    KQL

    operator                = "LessThan"
    threshold               = 1
    time_aggregation_method = "Maximum"
    metric_measure_column   = "MatchingServices"
  }

  action {
    action_groups = [azurerm_monitor_action_group.ai_smart_detection.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "aks_orders_api_unhealthy" {
  count               = local.aks_enabled ? 1 : 0
  name                = "alert-aks-orders-api-unhealthy"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  tags                = var.tags
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_log_analytics_workspace.law,
  ]

  description             = "AKS: one or more orders-api pods are not running, failing probes, stuck (e.g. ErrImagePull), or restarting."
  display_name            = "AKS orders-api workload unhealthy"
  severity                = 1
  enabled                 = true
  evaluation_frequency    = "PT5M"
  window_duration         = "PT10M"
  auto_mitigation_enabled = true
  skip_query_validation   = true
  scopes                  = [azurerm_log_analytics_workspace.law.id]

  criteria {
    # A pod counts as unhealthy when it still exists, has been unhealthy for at
    # least two inventory snapshots (~2 min, so normal rollouts don't fire),
    # restarted within the window, or is failing readiness/liveness probes.
    query = <<-KQL
      let Pods = union isfuzzy=true
        (KubePodInventory
          | project TimeGenerated, ClusterName = tostring(column_ifexists("ClusterName", "")), Namespace = tostring(column_ifexists("Namespace", "")), Name = tostring(column_ifexists("Name", "")), ContainerName = tostring(column_ifexists("ContainerName", "")), PodStatus = tostring(column_ifexists("PodStatus", "")), ContainerStatus = tostring(column_ifexists("ContainerStatus", "")), ContainerStatusReason = tostring(column_ifexists("ContainerStatusReason", "")), PodRestartCount = tolong(column_ifexists("PodRestartCount", 0)), PodLabel = tostring(column_ifexists("PodLabel", ""))),
        (datatable(TimeGenerated:datetime, ClusterName:string, Namespace:string, Name:string, ContainerName:string, PodStatus:string, ContainerStatus:string, ContainerStatusReason:string, PodRestartCount:long, PodLabel:string)[]);
      let Events = union isfuzzy=true
        (KubeEvents
          | project TimeGenerated, ClusterName = tostring(column_ifexists("ClusterName", "")), Name = tostring(column_ifexists("Name", "")), Reason = tostring(column_ifexists("Reason", "")), Message = tostring(column_ifexists("Message", ""))),
        (datatable(TimeGenerated:datetime, ClusterName:string, Name:string, Reason:string, Message:string)[]);
      let ClusterPods = Pods
        | where TimeGenerated > ago(10m)
        | where ClusterName startswith "aks-";
      let LatestBatch = toscalar(ClusterPods | summarize max(TimeGenerated));
      let ProbeFailing = Events
        | where TimeGenerated > ago(5m)
        | where ClusterName startswith "aks-" and Name startswith "orders-api-"
        | where Reason == "Unhealthy"
        | distinct Name
        | extend ProbeFailed = 1;
      ClusterPods
      | where Name startswith "orders-api-"
      | extend Unhealthy = PodStatus != "Terminating" and not(PodStatus == "Running" and ((ContainerStatus == "running" and isempty(ContainerStatusReason)) or (ContainerStatus == "terminated" and ContainerStatusReason == "Completed")))
      | summarize LastSeen = max(TimeGenerated), UnhealthySnapshots = dcountif(TimeGenerated, Unhealthy), LatestUnhealthy = countif(Unhealthy and TimeGenerated >= LatestBatch - 30s), RestartDelta = max(PodRestartCount) - min(PodRestartCount) by Name
      | where LastSeen >= LatestBatch - 30s
      | join kind=leftouter ProbeFailing on Name
      | summarize UnhealthyPods = countif((LatestUnhealthy > 0 and UnhealthySnapshots >= 2) or RestartDelta > 0 or coalesce(ProbeFailed, 0) == 1)
      | extend UnhealthyPods = coalesce(UnhealthyPods, 0)
    KQL

    operator                = "GreaterThan"
    threshold               = 0
    time_aggregation_method = "Maximum"
    metric_measure_column   = "UnhealthyPods"
  }

  action {
    action_groups = [azurerm_monitor_action_group.ai_smart_detection.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "aks_orders_api_service_no_endpoints" {
  count               = local.aks_enabled ? 1 : 0
  name                = "alert-aks-orders-api-service-no-endpoints"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  tags                = var.tags
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_log_analytics_workspace.law,
  ]

  description             = "AKS: an orders-api service selects no healthy pods although healthy orders-api pods run in its namespace (selector or label mismatch)."
  display_name            = "AKS orders-api service has no endpoints"
  severity                = 1
  enabled                 = true
  evaluation_frequency    = "PT5M"
  window_duration         = "PT5M"
  auto_mitigation_enabled = true
  skip_query_validation   = true
  scopes                  = [azurerm_log_analytics_workspace.law.id]

  criteria {
    # Fires only while healthy orders-api pods exist, so a full outage is left
    # to alert-aks-orders-api-unavailable instead of raising a duplicate incident.
    query = <<-KQL
      let Services = union isfuzzy=true
        (KubeServices
          | project TimeGenerated, ClusterName = tostring(column_ifexists("ClusterName", "")), Namespace = tostring(column_ifexists("Namespace", "")), ServiceName = tostring(column_ifexists("ServiceName", column_ifexists("Name", ""))), SelectorLabels = tostring(column_ifexists("SelectorLabels", ""))),
        (datatable(TimeGenerated:datetime, ClusterName:string, Namespace:string, ServiceName:string, SelectorLabels:string)[]);
      let Pods = union isfuzzy=true
        (KubePodInventory
          | project TimeGenerated, ClusterName = tostring(column_ifexists("ClusterName", "")), Namespace = tostring(column_ifexists("Namespace", "")), Name = tostring(column_ifexists("Name", "")), ContainerName = tostring(column_ifexists("ContainerName", "")), PodStatus = tostring(column_ifexists("PodStatus", "")), ContainerStatus = tostring(column_ifexists("ContainerStatus", "")), ContainerStatusReason = tostring(column_ifexists("ContainerStatusReason", "")), PodRestartCount = tolong(column_ifexists("PodRestartCount", 0)), PodLabel = tostring(column_ifexists("PodLabel", ""))),
        (datatable(TimeGenerated:datetime, ClusterName:string, Namespace:string, Name:string, ContainerName:string, PodStatus:string, ContainerStatus:string, ContainerStatusReason:string, PodRestartCount:long, PodLabel:string)[]);
      let Selector = Services
        | where TimeGenerated > ago(5m)
        | where ClusterName startswith "aks-" and ServiceName == "orders-api"
        | summarize arg_max(TimeGenerated, SelectorLabels) by Namespace
        | extend Parsed = parse_json(SelectorLabels)
        | mv-expand Item = iff(gettype(Parsed) == "array", Parsed, pack_array(Parsed))
        | mv-expand SelKey = bag_keys(Item) to typeof(string)
        | where isnotempty(SelKey)
        | project Namespace, SelKey, SelValue = tostring(Item[SelKey]);
      let SelectorKeys = Selector | summarize SelectorKeys = count() by Namespace;
      let ClusterPods = Pods
        | where TimeGenerated > ago(5m)
        | where ClusterName startswith "aks-";
      let LatestBatch = toscalar(ClusterPods | summarize max(TimeGenerated));
      let ReadyPods = ClusterPods
        | summarize arg_max(TimeGenerated, PodStatus, ContainerStatus, ContainerStatusReason, PodLabel) by Namespace, Name, ContainerName
        | where TimeGenerated >= LatestBatch - 30s
        | summarize UnhealthyContainers = countif(not(PodStatus == "Running" and ((ContainerStatus == "running" and isempty(ContainerStatusReason)) or (ContainerStatus == "terminated" and ContainerStatusReason == "Completed")))), PodLabel = take_any(PodLabel) by Namespace, Name
        | where UnhealthyContainers == 0;
      let Endpoints = ReadyPods
        | extend Parsed = parse_json(PodLabel)
        | mv-expand Item = iff(gettype(Parsed) == "array", Parsed, pack_array(Parsed))
        | mv-expand LabelKey = bag_keys(Item) to typeof(string)
        | extend LabelValue = tostring(Item[LabelKey])
        | join kind=inner Selector on $left.Namespace == $right.Namespace, $left.LabelKey == $right.SelKey, $left.LabelValue == $right.SelValue
        | summarize MatchedKeys = dcount(LabelKey) by Namespace, Name
        | join kind=inner SelectorKeys on Namespace
        | where MatchedKeys == SelectorKeys
        | summarize Endpoints = dcount(Name) by Namespace;
      let HealthyOrdersPods = ReadyPods
        | where Name startswith "orders-api-"
        | summarize HealthyOrdersPods = count() by Namespace;
      SelectorKeys
      | join kind=inner HealthyOrdersPods on Namespace
      | join kind=leftouter Endpoints on Namespace
      | summarize ServicesWithoutEndpoints = countif(coalesce(Endpoints, 0) == 0)
    KQL

    operator                = "GreaterThan"
    threshold               = 0
    time_aggregation_method = "Maximum"
    metric_measure_column   = "ServicesWithoutEndpoints"
  }

  action {
    action_groups = [azurerm_monitor_action_group.ai_smart_detection.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "aks_pod_failures" {
  count               = local.aks_enabled ? 1 : 0
  name                = "alert-aks-pod-failures"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  tags                = var.tags
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_log_analytics_workspace.law,
  ]

  description             = "AKS: a pod in any namespace is Failed or Pending, or a container is stuck waiting."
  display_name            = "AKS - Failed or pending pods"
  severity                = 1
  enabled                 = true
  evaluation_frequency    = "PT1M"
  window_duration         = "PT5M"
  auto_mitigation_enabled = true
  skip_query_validation   = true
  scopes                  = [azurerm_log_analytics_workspace.law.id]

  criteria {
    query = <<-KQL
      KubePodInventory
      | where TimeGenerated > ago(2m)
      | where ClusterName startswith "aks-"
      | summarize arg_max(TimeGenerated, *) by ContainerName
      | where PodStatus in ("Failed", "Pending") or ContainerStatus =~ "waiting"
      // Normal pod start-up states, not failures.
      | where ContainerStatusReason !in ("ContainerCreating", "PodInitializing")
    KQL

    operator                = "GreaterThan"
    threshold               = 0
    time_aggregation_method = "Count"
  }

  action {
    action_groups = [azurerm_monitor_action_group.ai_smart_detection.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "aks_pod_restarts" {
  count               = local.aks_enabled ? 1 : 0
  name                = "alert-aks-pod-restarts"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  tags                = var.tags
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_log_analytics_workspace.law,
  ]

  description             = "AKS: a container restart count increased in any namespace in the last 5 minutes."
  display_name            = "AKS - Pod restart spike"
  severity                = 1
  enabled                 = true
  evaluation_frequency    = "PT1M"
  window_duration         = "PT5M"
  auto_mitigation_enabled = true
  skip_query_validation   = true
  scopes                  = [azurerm_log_analytics_workspace.law.id]

  criteria {
    query = <<-KQL
      KubePodInventory
      | where TimeGenerated > ago(5m)
      | where ClusterName startswith "aks-"
      | summarize FirstRestartCount = min(ContainerRestartCount), LastRestartCount = max(ContainerRestartCount) by ContainerName
      | where LastRestartCount > FirstRestartCount
    KQL

    operator                = "GreaterThan"
    threshold               = 0
    time_aggregation_method = "Count"
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
  scope_resource_ids  = [azapi_resource.ai[0].id]
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
