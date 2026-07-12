resource "azapi_resource" "sre_agent" {
  schema_validation_enabled = false
  type                      = "Microsoft.App/agents@2026-01-01"
  name                      = var.agent_name
  location                  = var.location
  parent_id                 = azurerm_resource_group.agent.id
  tags                      = var.tags

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [local.effective_identity_id]
  }

  body = {
    properties = {
      knowledgeGraphConfiguration = {
        identity = local.effective_identity_id
        # Always include the agent's own RG (where orders-api / change-lookup live)
        # plus any extra RGs the caller listed in target_resource_groups.
        managedResources = distinct(concat(
          ["/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.agent.name}"],
          [for rg in var.target_resource_groups : "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${rg}"]
        ))
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
      }
    }
  }

  depends_on = [
    azurerm_role_assignment.target_reader,
    azurerm_role_assignment.target_log_reader,
    azurerm_role_assignment.target_contributor,
    azurerm_role_assignment.monitoring_reader,
  ]
}