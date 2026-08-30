locals {
  app_service_plan = "asp-${local.suffix}"
}

resource "azurerm_service_plan" "webapps" {
  count               = local.webapps_enabled ? 1 : 0
  name                = local.app_service_plan
  resource_group_name = azurerm_resource_group.agent.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "B1"
  tags                = var.tags
}

resource "azurerm_linux_web_app" "orders_api" {
  count               = local.webapps_enabled ? 1 : 0
  name                = "orders-api-${local.suffix}"
  resource_group_name = azurerm_resource_group.agent.name
  location            = var.location
  service_plan_id     = azurerm_service_plan.webapps[0].id
  https_only          = true
  tags                = var.tags
  depends_on          = [azurerm_role_assignment.apps_acrpull]

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.apps[0].id]
  }

  site_config {
    always_on                                     = true
    health_check_path                             = "/health"
    container_registry_use_managed_identity       = true
    container_registry_managed_identity_client_id = azurerm_user_assigned_identity.apps[0].client_id

    application_stack {
      docker_image_name = "${azurerm_container_registry.acr[0].login_server}/orders-api:latest"
    }
  }

  app_settings = {
    APPLICATIONINSIGHTS_CONNECTION_STRING = local.effective_ai_conn_str
    WEBSITES_PORT                         = tostring(var.webapp_port)
  }
}

resource "azurerm_linux_web_app" "change_lookup" {
  count               = local.webapps_enabled ? 1 : 0
  name                = "change-lookup-${local.suffix}"
  resource_group_name = azurerm_resource_group.agent.name
  location            = var.location
  service_plan_id     = azurerm_service_plan.webapps[0].id
  https_only          = true
  tags                = var.tags
  depends_on          = [azurerm_role_assignment.apps_acrpull]

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.apps[0].id]
  }

  site_config {
    always_on                                     = false
    container_registry_use_managed_identity       = true
    container_registry_managed_identity_client_id = azurerm_user_assigned_identity.apps[0].client_id

    application_stack {
      docker_image_name = "${azurerm_container_registry.acr[0].login_server}/change-lookup:latest"
    }
  }

  app_settings = {
    APPLICATIONINSIGHTS_CONNECTION_STRING = local.effective_ai_conn_str
    WEBSITES_PORT                         = tostring(var.webapp_port)
  }
}