resource "azapi_resource" "sre_agent" {
  count                     = var.deploy_sre_agent ? 1 : 0
  schema_validation_enabled = false
  type                      = "Microsoft.App/agents@2026-01-01"
  name                      = var.agent_name
  location                  = var.location
  parent_id                 = azurerm_resource_group.agent.id
  tags                      = var.tags

  response_export_values = ["properties.agentEndpoint"]

  identity {
    type         = "UserAssigned"
    identity_ids = [local.effective_identity_id]
  }

  body = {
    properties = {
      knowledgeGraphConfiguration = {
        identity         = local.effective_identity_id
        managedResources = [for rg in var.target_resource_groups : "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${rg}"]
      }
      actionConfiguration = {
        accessLevel = var.access_level
        identity    = local.effective_identity_id
        mode        = var.action_mode
      }
      logConfiguration = {
        applicationInsightsConfiguration = {
          appId            = local.effective_ai_app_id
          connectionString = local.effective_ai_conn_str
        }
      }
      upgradeChannel        = var.upgrade_channel
      monthlyAgentUnitLimit = var.monthly_agent_unit_limit
      defaultModel = {
        provider = var.default_model_provider
        name     = var.default_model_name
      }
      incidentManagementConfiguration = var.enable_service_now_connector ? {
        type           = "ServiceNow"
        connectionName = "servicenow"
        connectionUrl  = var.service_now_instance
        connectionKey = jsonencode({
          endpoint = var.service_now_instance
          username = var.service_now_username
          password = var.service_now_password
        })
        } : {
        type           = "AzMonitor"
        connectionName = "azmonitor"
      }
      experimentalSettings = {
        EnableWorkspaceTools = true
        EnableHttpTriggers   = true
        EnableV2AgentLoop    = true
        EnableDevOpsTools    = true
        EnablePythonTools    = true
      }
      # VNet integration (free: no NICs are created in the subscription). Sandbox
      # traffic to Azure goes through the subnet; package registries, GitHub and
      # remote MCP stay on the managed path so no NAT gateway or firewall is needed.
      vnetConfiguration = local.vnet_enabled ? {
        subnetResourceId = local.effective_subnet_id
      } : null
      sandboxConfiguration = local.vnet_enabled ? {
        egress = {
          mode                            = "AzureVNet"
          allowedHosts                    = []
          allowedRegistries               = ["pypi", "npmjs"]
          allowedCodeRepositories         = ["Github"]
          allowHttpMcpServerNetworkAccess = true
          vnetConfiguration = {
            usePrivateDnsResolution = true
          }
        }
      } : null
    }
  }

  depends_on = [
    azurerm_role_assignment.monitoring_contributor,
    azurerm_role_assignment.monitoring_reader,
    azurerm_role_assignment.self_log_reader,
    azurerm_subnet.agent,
  ]
}
