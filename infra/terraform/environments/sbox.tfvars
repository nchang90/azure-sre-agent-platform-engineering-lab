agent_name               = "sre-agent-sbox"
resource_group_name      = "rg-sre-lab-sbox"
location                 = "uksouth"
target_resource_groups   = []
access_level             = "High"
action_mode              = "Review"
upgrade_channel          = "Preview"
monthly_agent_unit_limit = 10000
default_model_provider   = "MicrosoftFoundry"
default_model_name       = "Automatic"

tags = {
  environment = "sbox"
  project     = "sre-agent"
  scenario    = "s2"
}

email_receiver_address = "nicholasc001@hotmail.com"

admin_principal_ids = [
  "092b4414-2bb9-432d-abb2-9e407bf74125",
  "3a168e0b-7a73-4dd0-a4f8-80045502775b"
]

deploy_sre_agent = true

# S2 runtime scenario uses the Container Apps stack without AKS.
deploy_aks = false

# S2 needs the agent to see app telemetry and route Azure Monitor incidents.
enable_app_insights_connector  = true
enable_log_analytics_connector = true
enable_sev01_incident_filter   = true
enable_daily_health_check      = false
