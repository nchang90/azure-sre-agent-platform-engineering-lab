terraform {
  required_version = ">= 1.5"

  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
  }

  backend "azurerm" {
    subscription_id       = "64681aa1-73cc-4155-aa97-caa0e4837412"
    resource_group_name  = "terraform-tfstate-rg"
    storage_account_name = "terraformstatesbox"
    container_name       = "tfstate"
    key                  = "azuresre.tfstate"
  }
}

provider "azapi" {}

provider "azurerm" {
  features {}
}