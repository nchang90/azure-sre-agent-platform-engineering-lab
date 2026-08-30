agent_name               = "sre-agent-dev"
resource_group_name      = "rg-sre-lab-dev"
location                 = "uksouth"
target_resource_groups   = []
scenario                 = "s4"
access_level             = "Low"
action_mode              = "Review"
upgrade_channel          = "Preview"
monthly_agent_unit_limit = 10000
default_model_provider   = "MicrosoftFoundry"
default_model_name       = "Automatic"

tags = {
  environment = "dev"
  project     = "sre-agent"
  scenario    = "s4"
}

email_receiver_address = "replace-with-your-email@example.com"

deploy_sre_agent = true

webapp_port = 8080

enable_app_insights_connector  = true
enable_log_analytics_connector = true
enable_sev01_incident_filter   = true
enable_daily_health_check      = false
