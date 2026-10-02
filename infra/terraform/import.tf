import {
  for_each = var.resource_group_name == "rg-sre-lab-dev" && local.create_identity ? toset(["dev"]) : toset([])
  to       = azurerm_user_assigned_identity.agent[0]
  id       = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${var.agent_name}-id-${local.suffix}"
}

import {
  for_each = var.resource_group_name == "rg-sre-lab-dev" && local.images_enabled ? toset(["dev"]) : toset([])
  to       = azurerm_user_assigned_identity.apps[0]
  id       = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-apps-${local.suffix}"
}

import {
  for_each = var.resource_group_name == "rg-sre-lab-dev" && local.webapps_enabled ? toset(["dev"]) : toset([])
  to       = azurerm_service_plan.webapps[0]
  id       = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Web/serverFarms/asp-${local.suffix}"
}
