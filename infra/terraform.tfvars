agent_name               = "sre-agent"
resource_group_name      = "rg-sre-lab"
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
