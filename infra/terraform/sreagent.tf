resource "azapi_resource" "sre_agent" {
  count                     = var.deploy_sre_agent ? 1 : 0
  schema_validation_enabled = false
  type                      = "Microsoft.App/agents@2025-05-01-preview"
  name                      = var.agent_name
  location                  = var.location
  parent_id                 = azurerm_resource_group.agent.id
  tags                      = var.tags

  response_export_values = ["properties.agentEndpoint"]

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [local.effective_identity_id]
  }

  body = {
    properties = merge(
      {
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
        experimentalSettings = {
          EnableWorkspaceTools = true
          EnableHttpTriggers   = true
          EnableV2AgentLoop    = true
          EnableDevOpsTools    = true
          EnablePythonTools    = true
        }
      },
      local.network_config
    )
  }

  # self_smi_reader / self_smi_log_reader are intentionally NOT listed here:
  # they target the agent's own system-assigned identity, so they must be
  # created after this resource. Listing them would form a dependency cycle.
  depends_on = [
    azurerm_role_assignment.monitoring_reader,
    azurerm_role_assignment.self_log_reader,
    azurerm_subnet.agent,
  ]
}
