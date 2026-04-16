terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.117"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # ---------------------------------------------------------------------------
  # Remote state in Azure Blob Storage — separate key from dev.
  # Use the same state storage account bootstrapped for dev, or a dedicated one
  # for stronger blast-radius isolation between environments.
  # ---------------------------------------------------------------------------
  backend "azurerm" {
  }
}
