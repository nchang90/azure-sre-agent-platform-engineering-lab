output "agent_id" {
  description = "Full ARM resource ID of the SRE Agent."
  value       = var.deploy_sre_agent ? azapi_resource.sre_agent[0].id : ""
}

output "agent_portal_url" {
  description = "Direct link to the agent in the SRE Agent portal."
  value       = "https://sre.azure.com/#/agent/${data.azurerm_subscription.current.subscription_id}/${azurerm_resource_group.agent.name}/${var.agent_name}"
}

output "agent_data_plane_url" {
  description = "Agent data plane endpoint (real host read from the resource)."
  value       = var.deploy_sre_agent ? try(azapi_resource.sre_agent[0].output.properties.agentEndpoint, "https://${var.agent_name}.${var.location}.azuresre.ai") : ""
}

output "managed_identity_id" {
  description = "Resource ID of the User-Assigned Managed Identity used by the agent."
  value       = local.effective_identity_id
}

output "law_id" {
  description = "Resource ID of the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.law.id
}

output "resource_group_portal_url" {
  description = "Link to the agent resource group in the Azure portal."
  value       = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.agent.name}/overview"
}

# ── App outputs (only set when deploy_apps = true) ──

output "acr_name" {
  description = "Azure Container Registry name (for ACR-Tasks builds)."
  value       = local.apps_enabled ? azurerm_container_registry.acr[0].name : ""
}

output "acr_login_server" {
  description = "Azure Container Registry login server."
  value       = local.apps_enabled ? azurerm_container_registry.acr[0].login_server : ""
}

output "container_app_environment_id" {
  description = "Container Apps Environment resource ID."
  value       = local.apps_enabled ? azurerm_container_app_environment.cae[0].id : ""
}

output "orders_api_name" {
  description = "Name of the orders-api Container App."
  value       = local.apps_enabled ? azurerm_container_app.orders_api[0].name : ""
}

output "orders_api_url" {
  description = "Public URL of orders-api."
  value       = local.apps_enabled ? "https://${azurerm_container_app.orders_api[0].latest_revision_fqdn}" : ""
}

output "change_lookup_name" {
  description = "Name of the change-lookup Container App."
  value       = local.apps_enabled ? azurerm_container_app.change_lookup[0].name : ""
}

output "change_lookup_url" {
  description = "Public URL of change-lookup."
  value       = local.apps_enabled ? "https://${azurerm_container_app.change_lookup[0].latest_revision_fqdn}" : ""
}

output "orders_api_health_alert_id" {
  description = "Resource ID of the orders-api health scheduled query alert."
  value       = local.apps_enabled ? azurerm_monitor_scheduled_query_rules_alert_v2.orders_api_health[0].id : ""
}

output "action_mode" {
  description = "Agent action mode (Review or Automatic)."
  value       = var.action_mode
}

output "vnet_id" {
  description = "Resource ID of the VNet created for VNet integration (empty if disabled or BYO subnet)."
  value       = local.create_vnet ? azurerm_virtual_network.agent[0].id : ""
}

output "agent_subnet_id" {
  description = "Resource ID of the dedicated agent subnet used for VNet integration."
  value       = local.vnet_enabled ? local.effective_subnet_id : ""
}
