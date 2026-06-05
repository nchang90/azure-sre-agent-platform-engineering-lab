# Import existing apps when they already exist in Azure but are missing from state.
import {
  to = azurerm_container_app.orders_api[0]
  id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.App/containerApps/orders-api"
}

import {
  to = azurerm_container_app.change_lookup[0]
  id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.App/containerApps/change-lookup"
}
