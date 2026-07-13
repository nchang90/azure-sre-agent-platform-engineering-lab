agent_name               = "sre-agent-sbox"
resource_group_name      = "rg-sre-lab-sbox"
location                 = "uksouth"
target_resource_groups   = []
access_level             = "Low"
action_mode              = "Review"
upgrade_channel          = "Preview"
monthly_agent_unit_limit = 10000
default_model_provider   = "MicrosoftFoundry"
default_model_name       = "Automatic"

tags = {
  environment = "sbox"
  project     = "sre-agent"
  scenario    = "s1"
}

email_receiver_address = "nicholasc001@hotmail.com"

admin_principal_ids = [
  "092b4414-2bb9-432d-abb2-9e407bf74125",
  "3a168e0b-7a73-4dd0-a4f8-80045502775b"
]

deploy_sre_agent = true
# Keep the Container Apps stack for sandbox; AKS stays disabled here.
deploy_apps                    = true
deploy_aks                     = false
# Sandbox now gets its own VNet for the agent stack.
enable_vnet                    = true
enable_app_insights_connector  = false
enable_log_analytics_connector = false
enable_sev01_incident_filter   = false
enable_daily_health_check      = false