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
  sku_tier            = "Standard"

  automatic_upgrade_channel = "stable"
  azure_policy_enabled      = true
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks[0].id]
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  }

  default_node_pool {
    name                         = "sys"
    vm_size                      = var.aks_node_vm_size
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
