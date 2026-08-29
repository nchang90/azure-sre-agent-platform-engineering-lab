# Recipe-specific variables for ServiceNow + AKS integration

variable "resource_group_name" {
  description = "Resource group that holds the agent and supporting resources."
  type        = string
}

variable "scenario" {
  description = "Scenario selector (s1-s6). This recipe is used by s3."
  type        = string
  validation {
    condition     = contains(["s1", "s2", "s3", "s4", "s5", "s6"], var.scenario)
    error_message = "scenario must be s1-s6."
  }
}

variable "location" {
  description = "Azure region for resources."
  type        = string
  default     = "uksouth"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "existing_agent_app_insights_id" {
  description = "Resource ID of existing Application Insights for agent telemetry."
  type        = string
  default     = ""
}

variable "law_resource_id" {
  description = "Full Azure resource ID of the Log Analytics workspace."
  type        = string
  default     = ""
}

variable "enable_service_now_connector" {
  description = "Enable ServiceNow connector. Defaults to true for this recipe."
  type        = bool
  default     = true
}

variable "aks_cluster_name" {
  description = "Name of the AKS cluster being monitored by this recipe."
  type        = string
  default     = ""
}

variable "aks_resource_group_name" {
  description = "Resource group containing the AKS cluster."
  type        = string
  default     = ""
}

variable "servicenow_instance_url" {
  description = "ServiceNow instance URL (e.g., https://dev12345.service-now.com)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "servicenow_client_id" {
  description = "ServiceNow OAuth2 client ID."
  type        = string
  default     = ""
  sensitive   = true
}

variable "servicenow_client_secret" {
  description = "ServiceNow OAuth2 client secret."
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for incident notifications."
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_daily_health_check" {
  description = "Enable daily AKS cluster health check automation."
  type        = bool
  default     = true
}

variable "health_check_schedule" {
  description = "Cron schedule for daily health check (UTC). Default: 8 AM UTC."
  type        = string
  default     = "0 8 * * *"
}
