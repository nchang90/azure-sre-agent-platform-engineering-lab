variable "agent_name" {
  description = "Agent name (lowercase, no spaces)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$", var.agent_name))
    error_message = "agent_name must be lowercase alphanumeric with hyphens, 2-63 chars."
  }
}

variable "severity_threshold" {
  description = "Severity level for the failure anomalies smart detector alert."
  type        = string
  default     = "Sev1"
}


variable "email_receiver_address" {
  description = "Email address for action group notifications (used by smart detector alert rule)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that holds the agent, identity, LAW, and App Insights."
  type        = string
}

variable "location" {
  description = "Azure region. Only regions supported by the SRE Agent RP."
  type        = string
  default     = "eastus2"

  validation {
    condition     = contains(["swedencentral", "uksouth", "eastus2", "australiaeast"], var.location)
    error_message = "location must be one of: swedencentral, uksouth, eastus2, australiaeast."
  }
}

variable "target_resource_groups" {
  description = "Resource group names the agent is granted access to."
  type        = list(string)
  default     = []
}

variable "access_level" {
  description = "Low = read-only investigation. High = can take actions."
  type        = string
  default     = "Low"

  validation {
    condition     = contains(["High", "Low"], var.access_level)
    error_message = "access_level must be High or Low."
  }
}

variable "action_mode" {
  description = "Review = human approval. Automatic = agent acts independently."
  type        = string
  default     = "Review"

  validation {
    condition     = contains(["Review", "Automatic"], var.action_mode)
    error_message = "action_mode must be Review or Automatic."
  }
}

variable "upgrade_channel" {
  description = "Upgrade channel for the agent runtime."
  type        = string
  default     = "Preview"

  validation {
    condition     = contains(["Stable", "Preview"], var.upgrade_channel)
    error_message = "upgrade_channel must be Stable or Preview."
  }
}

variable "monthly_agent_unit_limit" {
  description = "Monthly agent unit consumption limit."
  type        = number
  default     = 10000
}

variable "default_model_provider" {
  description = "Default LLM provider (MicrosoftFoundry, Anthropic)."
  type        = string
  default     = "Anthropic"
}

variable "default_model_name" {
  description = "Default LLM model name."
  type        = string
  default     = "Automatic"
}

variable "tags" {
  description = "Azure resource tags applied to the agent and supporting resources."
  type        = map(string)
  default     = {}
}

# ── Admin principals ──

variable "admin_principal_ids" {
  description = "Object IDs of users or service principals to grant SRE Agent Administrator on the agent resource."
  type        = list(string)
  default     = []
}

# ── Identity ──

variable "existing_managed_identity_id" {
  description = "Resource ID of an existing UAMI. If provided, skips creating a new one."
  type        = string
  default     = ""
}

variable "existing_agent_app_insights_id" {
  description = "Resource ID of an existing Application Insights for agent telemetry. If provided, skips creating a new one."
  type        = string
  default     = ""
}

# ── Connector toggles ──

variable "enable_app_insights_connector" {
  description = "Enable an Application Insights connector."
  type        = bool
  default     = false
}

variable "app_insights_resource_id" {
  description = "Full Azure resource ID of the App Insights component."
  type        = string
  default     = ""
}

variable "app_insights_app_id" {
  description = "App Insights Application ID (GUID from the Overview blade)."
  type        = string
  default     = ""
}

variable "enable_log_analytics_connector" {
  description = "Enable a Log Analytics connector."
  type        = bool
  default     = false
}

variable "law_resource_id" {
  description = "Full Azure resource ID of the LAW workspace."
  type        = string
  default     = ""
}

variable "enable_azure_monitor_connector" {
  description = "Enable an Azure Monitor connector (subscription-scoped alerts)."
  type        = bool
  default     = false
}

variable "azure_monitor_lookback_days" {
  description = "Lookback window in days for the Azure Monitor connector."
  type        = number
  default     = 7
}

# ── Recipe automations (azmon-lawappinsights) ──
# Opt-in per environment. Applied at the data plane by scripts/post-provision.sh.

variable "enable_sev01_incident_filter" {
  description = "Create the azmon-sev01 response plan (Sev0/Sev1 Azure Monitor alerts → alert-investigator, autonomous)."
  type        = bool
  default     = false
}

variable "enable_daily_health_check" {
  description = "Create the daily-health-check scheduled task (daily 08:00 resource-health summary → alert-investigator)."
  type        = bool
  default     = false
}

# ── Extension arrays (advanced) ──

variable "skills" {
  description = "Skill definitions. Each entry: { name, spec = { ... } }."
  type = list(object({
    name = string
    spec = any
  }))
  default = []
}

variable "subagents" {
  description = "Subagent definitions. Each entry: { name, spec = { ... } }."
  type = list(object({
    name = string
    spec = any
  }))
  default = []
}

variable "connectors" {
  description = "Additional connector definitions (beyond toggle-generated ones). Each entry: { name, properties = { dataConnectorType, dataSource, extendedProperties, identity } }."
  type        = any
  default     = []
}

variable "common_prompts" {
  description = "Common prompt definitions. Each entry: { name, properties = { prompt } }."
  type = list(object({
    name       = string
    properties = any
  }))
  default = []
}

variable "tools" {
  description = "Tool definitions. Each entry: { name, spec = { ... } }."
  type = list(object({
    name = string
    spec = any
  }))
  default = []
}

variable "enable_webhook_bridge" {
  description = "Deploy a Logic App webhook bridge for HTTP trigger ingestion."
  type        = bool
  default     = false
}

variable "webhook_bridge_trigger_url" {
  description = "Pre-existing webhook trigger URL (skip Logic App creation if set)."
  type        = string
  default     = ""
}

variable "deploy_sre_agent" {
  description = "Deploy the SRE Agent resource."
  type        = bool
}

# ── Network integration ──

variable "enable_vnet" {
  description = "Enable Azure VNet integration (Azure VNet egress mode). Creates a VNet and dedicated subnet delegated to Microsoft.App/environments."
  type        = bool
  default     = false
}

variable "vnet_address_space" {
  description = "Address space for the VNet created when enable_vnet = true."
  type        = string
  default     = "10.0.0.0/16"
}

variable "agent_subnet_prefix" {
  description = "CIDR for the dedicated agent subnet. Must be /28 or larger."
  type        = string
  default     = "10.0.0.0/28"
}

variable "existing_subnet_id" {
  description = "Resource ID of an existing subnet to use for VNet integration. If set, no VNet is created and enable_vnet is implied."
  type        = string
  default     = ""
}