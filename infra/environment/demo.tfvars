agent_name               = "sre-agent-platform"
resource_group_name      = "rg-sre-lab-demo"
location                 = "uksouth"
target_resource_groups   = []
access_level             = "Low"
action_mode              = "Review"
upgrade_channel          = "Preview"
monthly_agent_unit_limit = 10000
default_model_provider   = "MicrosoftFoundry"
default_model_name       = "Automatic"

tags = {
  environment = "lab"
  project     = "sre-agent"
}

email_receiver_address = "nicholasc001@hotmail.com"

admin_principal_ids = [
  "092b4414-2bb9-432d-abb2-9e407bf74125",
  "3a168e0b-7a73-4dd0-a4f8-80045502775b"
]

deploy_sre_agent = true

# ── Recipe automations (azmon-lawappinsights) — enabled for the demo environment ──
enable_sev01_incident_filter = true
enable_daily_health_check    = true