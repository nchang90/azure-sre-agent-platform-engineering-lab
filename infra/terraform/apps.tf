variable "deploy_apps" {
  description = "Deploy the orders-api and change-lookup Container Apps."
  type        = bool
  default     = true
}

variable "acr_sku" {
  description = "SKU for the Azure Container Registry."
  type        = string
  default     = "Basic"
}

locals {
  apps_enabled      = var.deploy_apps
  acr_name          = "acr${replace(local.suffix, "-", "")}"
  cae_name          = "cae-${local.suffix}"
  uami_apps_name    = "id-apps-${local.suffix}"
  placeholder_image = "mcr.microsoft.com/k8se/quickstart:latest"
}

resource "azurerm_container_registry" "acr" {
  count               = local.apps_enabled ? 1 : 0
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.agent.name
  location            = var.location
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "apps" {
  count               = local.apps_enabled ? 1 : 0
  name                = local.uami_apps_name
  resource_group_name = azurerm_resource_group.agent.name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "apps_acrpull" {
  count                = local.apps_enabled ? 1 : 0
  scope                = azurerm_container_registry.acr[0].id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.apps[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_container_app_environment" "cae" {
  count                      = local.apps_enabled ? 1 : 0
  name                       = local.cae_name
  resource_group_name        = azurerm_resource_group.agent.name
  location                   = var.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  tags                       = var.tags
}

resource "azurerm_container_app" "orders_api" {
  count                        = local.apps_enabled ? 1 : 0
  name                         = "orders-api"
  resource_group_name          = azurerm_resource_group.agent.name
  container_app_environment_id = azurerm_container_app_environment.cae[0].id
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.apps[0].id]
  }

  registry {
    server   = azurerm_container_registry.acr[0].login_server
    identity = azurerm_user_assigned_identity.apps[0].id
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "auto"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 3

    container {
      name   = "orders-api"
      image  = local.placeholder_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = local.effective_ai_conn_str
      }
      env {
        name  = "ACTIVE_CR"
        value = ""
      }

      liveness_probe {
        transport               = "HTTP"
        path                    = "/health"
        port                    = 8080
        initial_delay           = 5
        interval_seconds        = 10
        failure_count_threshold = 3
      }
    }
  }

  lifecycle {
    # post-provision script updates the image; don't fight that on re-apply
    ignore_changes = [template[0].container[0].image]
  }
}

resource "azurerm_container_app" "change_lookup" {
  count                        = local.apps_enabled ? 1 : 0
  name                         = "change-lookup"
  resource_group_name          = azurerm_resource_group.agent.name
  container_app_environment_id = azurerm_container_app_environment.cae[0].id
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.apps[0].id]
  }

  registry {
    server   = azurerm_container_registry.acr[0].login_server
    identity = azurerm_user_assigned_identity.apps[0].id
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "auto"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 2

    container {
      name   = "change-lookup"
      image  = local.placeholder_image
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }
}
