# Output values for ServiceNow + AKS recipe

output "recipe_name" {
  description = "Name of the recipe deployed."
  value       = "servicenow-aks-incident"
}

output "scenario_configured" {
  description = "Scenario this recipe is configured for."
  value       = var.scenario
}

output "servicenow_connector_enabled" {
  description = "Whether the ServiceNow connector is enabled."
  value       = var.enable_service_now_connector
}

output "aks_cluster_monitored" {
  description = "AKS cluster name being monitored."
  value       = var.aks_cluster_name
}

output "app_insights_resource_id" {
  description = "Application Insights resource ID used for telemetry."
  value       = var.existing_agent_app_insights_id
}

output "law_workspace_resource_id" {
  description = "Log Analytics workspace resource ID for KQL queries."
  value       = var.law_resource_id
}

output "health_check_automation_enabled" {
  description = "Whether the daily health check automation is enabled."
  value       = var.enable_daily_health_check
}

output "health_check_schedule_cron" {
  description = "Cron schedule for health check automation (UTC)."
  value       = var.health_check_schedule
}
