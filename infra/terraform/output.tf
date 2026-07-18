output "agent_id" {
  description = "Full ARM resource ID of the SRE Agent."
  value       = azapi_resource.sre_agent[0].id
}

output "agent_portal_url" {
  description = "Direct link to the agent in the SRE Agent portal."
  value       = "https://sre.azure.com/#/agent/${data.azurerm_subscription.current.subscription_id}/${azurerm_resource_group.agent.name}/${var.agent_name}"
}

output "agent_data_plane_url" {
  description = "Agent data plane endpoint."
  value       = try(azapi_resource.sre_agent[0].output.properties.agentEndpoint, "")
}

output "managed_identity_id" {
  description = "Resource ID of the User-Assigned Managed Identity used by the agent."
  value       = local.effective_identity_id
}

output "agent_vnet_id" {
  description = "Resource ID of the virtual network used by Azure SRE Agent workspace egress."
  value       = local.create_vnet ? azurerm_virtual_network.agent[0].id : ""
}

output "agent_subnet_id" {
  description = "Resource ID of the delegated subnet used by Azure SRE Agent workspace egress."
  value       = local.vnet_enabled ? local.effective_subnet_id : ""
}

output "law_id" {
  description = "Resource ID of the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.law.id
}

output "resource_group_portal_url" {
  description = "Link to the agent resource group in the Azure portal."
  value       = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.agent.name}/overview"
}

output "aks_name" {
  description = "Name of the AKS cluster."
  value       = local.aks_enabled ? azurerm_kubernetes_cluster.aks[0].name : ""
}

output "aks_id" {
  description = "Resource ID of the AKS cluster."
  value       = local.aks_enabled ? azurerm_kubernetes_cluster.aks[0].id : ""
}

output "aks_node_resource_group" {
  description = "Node resource group created for the AKS cluster."
  value       = local.aks_enabled ? azurerm_kubernetes_cluster.aks[0].node_resource_group : ""
}

output "aks_kubelet_identity_object_id" {
  description = "Object ID of the AKS kubelet identity."
  value       = local.aks_enabled ? azurerm_kubernetes_cluster.aks[0].kubelet_identity[0].object_id : ""
}

output "aks_kubelet_identity_client_id" {
  description = "Client ID of the AKS kubelet identity."
  value       = local.aks_enabled ? azurerm_kubernetes_cluster.aks[0].kubelet_identity[0].client_id : ""
}

output "aks_identity_id" {
  description = "Resource ID of the managed identity assigned to AKS."
  value       = local.aks_enabled ? azurerm_user_assigned_identity.aks[0].id : ""
}

output "aks_vnet_id" {
  description = "Resource ID of the virtual network used by AKS."
  value       = local.aks_enabled ? azurerm_virtual_network.aks[0].id : ""
}

output "aks_subnet_id" {
  description = "Resource ID of the subnet used by AKS nodes."
  value       = local.aks_enabled ? azurerm_subnet.aks[0].id : ""
}

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
