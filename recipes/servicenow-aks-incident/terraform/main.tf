terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.90"
    }
  }
}

provider "azurerm" {
  features {}
}

# Local variables for recipe configuration
locals {
  recipe_name = "servicenow-aks-incident"
  
  # ServiceNow connector will be registered by apply-extras.sh
  # This file provides the infrastructure foundation for the recipe
  
  agent_display_name = "SRE Agent (ServiceNow + AKS)"
  
  # Tags applied to all resources
  common_tags = merge(
    var.tags,
    {
      recipe = local.recipe_name
      scenario = var.scenario
      created_by = "terraform"
    }
  )
}

# Data source for the agent resource group
data "azurerm_resource_group" "agent" {
  name = var.resource_group_name
}

# Data source for existing Application Insights (created by main provider)
data "azurerm_application_insights" "agent" {
  count               = var.existing_agent_app_insights_id != "" ? 1 : 0
  name                = split("/", var.existing_agent_app_insights_id)[8]
  resource_group_name = data.azurerm_resource_group.agent.name
}

# Data source for existing LAW (created by main provider)
data "azurerm_log_analytics_workspace" "agent" {
  count               = var.law_resource_id != "" ? 1 : 0
  name                = split("/", var.law_resource_id)[8]
  resource_group_name = data.azurerm_resource_group.agent.name
}
