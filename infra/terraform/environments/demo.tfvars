agent_name               = "sre-agent-platform"
resource_group_name      = "rg-sre-lab-demo"
location                 = "uksouth"
target_resource_groups   = []
scenario                 = "s3"
access_level             = "High"
action_mode              = "Review"
upgrade_channel          = "Preview"
monthly_agent_unit_limit = 10000
default_model_provider   = "MicrosoftFoundry"
default_model_name       = "Automatic"

tags = {
  environment = "demo"
  project     = "sre-agent"
  scenario    = "s3"
}

email_receiver_address = "nicholasc001@hotmail.com"

admin_principal_ids = [
  "092b4414-2bb9-432d-abb2-9e407bf74125",
  "3a168e0b-7a73-4dd0-a4f8-80045502775b"
]

standard_user_principal_ids = [
  "092b4414-2bb9-432d-abb2-9e407bf74125",
  "3a168e0b-7a73-4dd0-a4f8-80045502775b"
]

aks_min_count = 2

aks_max_count = 3

deploy_sre_agent = true

enable_vnet = false

enable_app_insights_connector  = true
enable_log_analytics_connector = true
enable_azure_monitor_connector = false

# S3 incident source: ServiceNow. Password comes from the environment, never tfvars.
enable_service_now_connector = true
service_now_instance         = "https://dev411761.service-now.com"
service_now_username         = "admin"

enable_sev01_incident_filter = true
enable_daily_health_check    = true
