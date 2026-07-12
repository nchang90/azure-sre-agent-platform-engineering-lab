# AKS-only demo settings for S3 Incident Root Cause Investigation.
# This keeps the Container Apps stack disabled while still deploying the SRE Agent.

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
deploy_apps              = false

aks_node_vm_size        = "Standard_B1s"
aks_node_count          = 2
aks_min_count           = 2
aks_max_count           = 3
aks_ssh_public_key_path = "~/.ssh/id_rsa.pub"
aks_pod_cidr            = "10.244.0.0/16"
aks_service_cidr        = "10.0.0.0/16"
aks_dns_service_ip      = "10.0.0.10"

tags = {
  environment = "demo"
  project     = "sre-agent"
}
