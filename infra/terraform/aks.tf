locals {
  aks_suffix = substr(sha256("${data.azurerm_subscription.current.subscription_id}-${var.resource_group_name}-aks"), 0, 8)
}

resource "tls_private_key" "aks_ssh" {
  count     = local.aks_enabled ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_kubernetes_cluster" "aks" {
  count               = local.aks_enabled ? 1 : 0
  name                = "aks-${local.aks_suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.agent.name
  dns_prefix          = "aks-${local.aks_suffix}"
  sku_tier            = var.aks_sku_tier

  automatic_upgrade_channel = "stable"
  azure_policy_enabled      = true
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks[0].id]
  }

  # Managed-identity auth so the Container Insights DCR below controls what is
  # collected. Without it the legacy agent ships Perf/ContainerInventory/
  # ContainerLog, which the alerts never read.
  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.law.id
    msi_auth_for_monitoring_enabled = true
  }

  default_node_pool {
    name                         = "sys"
    vm_size                      = var.aks_node_vm_size
    os_disk_size_gb              = var.aks_os_disk_size_gb
    temporary_name_for_rotation  = "systmp"
    auto_scaling_enabled         = true
    min_count                    = var.aks_min_count
    max_count                    = var.aks_max_count
    vnet_subnet_id               = azurerm_subnet.aks[0].id
    only_critical_addons_enabled = true
  }

  linux_profile {
    admin_username = "azureuser"

    ssh_key {
      key_data = tls_private_key.aks_ssh[0].public_key_openssh
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = var.aks_pod_cidr
    service_cidr        = var.aks_service_cidr
    dns_service_ip      = var.aks_dns_service_ip
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  tags = var.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  count                 = local.aks_enabled ? 1 : 0
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks[0].id
  vm_size               = var.aks_user_node_vm_size
  os_disk_size_gb       = var.aks_os_disk_size_gb
  mode                  = "User"
  auto_scaling_enabled  = true
  min_count             = var.aks_user_min_count
  max_count             = var.aks_user_max_count
  vnet_subnet_id        = azurerm_subnet.aks[0].id
  tags                  = var.tags
}

# Container Insights, cost-optimised: only the tables the S3 alerts and the
# agent's AKS triage query. Perf, ContainerInventory and ContainerLog were ~78%
# of workspace ingestion and nothing reads them.
locals {
  container_insights_streams = [
    "Microsoft-ContainerLogV2",
    "Microsoft-KubePodInventory",
    "Microsoft-KubeNodeInventory",
    "Microsoft-KubeEvents",
    "Microsoft-KubeServices",
    "Microsoft-InsightsMetrics",
  ]
}

resource "azurerm_monitor_data_collection_rule" "container_insights" {
  count               = local.aks_enabled ? 1 : 0
  name                = "dcr-ci-${local.aks_suffix}"
  resource_group_name = azurerm_resource_group.agent.name
  location            = var.location
  kind                = "Linux"
  tags                = var.tags

  destinations {
    log_analytics {
      name                  = "ciworkspace"
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
    }
  }

  data_flow {
    streams      = local.container_insights_streams
    destinations = ["ciworkspace"]
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = local.container_insights_streams
      extension_json = jsonencode({
        dataCollectionSettings = {
          # 1m keeps alert detection fast during the demo.
          interval               = "1m"
          namespaceFilteringMode = "Off"
          enableContainerLogV2   = true
        }
      })
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "container_insights" {
  count                   = local.aks_enabled ? 1 : 0
  name                    = "ContainerInsightsExtension"
  target_resource_id      = azurerm_kubernetes_cluster.aks[0].id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights[0].id
}
