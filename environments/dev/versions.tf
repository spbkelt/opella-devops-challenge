terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }

  # ---------------------------------------------------------------------------
  # Remote state in Azure Blob Storage.
  # Bootstrap once before the first `terraform init`:
  #
  #
  # Then init with:
  #   terraform init
  # ---------------------------------------------------------------------------
  backend "azurerm" {
  }
}
