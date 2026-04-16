locals {
  rg_name         = "rg-${var.project}-${var.environment}-${var.location}-001"
  vnet_name       = "vnet-${var.project}-${var.environment}-${var.location}-001"
  app_subnet_key  = "snet-app-${var.environment}-${var.location}-001"
  mgmt_subnet_key = "snet-mgmt-${var.environment}-${var.location}-001"

  region_short = {
    eastus        = "eus"
    eastus2       = "eus2"
    westus        = "wus"
    westus2       = "wus2"
    westus3       = "wus3"
    centralus     = "cus"
    northeurope   = "neu"
    westeurope    = "weu"
    uksouth       = "uks"
    ukwest        = "ukw"
    southeastasia = "sea"
    eastasia      = "ea"
    australiaeast = "aue"
  }

  vm_name          = "vm-${var.project}-${var.environment}-${var.location}-001"
  vm_computer_name = "vm-${local.region_short[var.location]}-${var.environment}-001"
  nic_name         = "nic-${var.project}-${var.environment}-${var.location}-001"
  pip_name         = "pip-${var.project}-${var.environment}-${var.location}-001"
  os_disk_name     = "osdisk-${var.project}-${var.environment}-${var.location}-001"

  storage_account_name = substr(
    "${replace(lower("st${var.project}${var.environment}${var.location}"), "-", "")}${random_string.storage_suffix.result}",
    0,
    24
  )

  storage_container = "data"

  common_tags = {
    environment = var.environment
    region      = var.location
    project     = var.project
    managed_by  = "terraform"
    owner       = var.owner
    cost_center = "dev-workloads"
  }

  subnets = {
    (local.app_subnet_key) = {
      address_prefix    = var.subnet_cidrs.app
      service_endpoints = ["Microsoft.Storage"]
      nsg_rules = [
        {
          name                       = "AllowSSHFromMgmt"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "22"
          source_address_prefix      = var.subnet_cidrs.mgmt
          destination_address_prefix = "*"
        },
        {
          name                       = "AllowHTTPS"
          priority                   = 200
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "443"
          source_address_prefix      = "Internet"
          destination_address_prefix = "*"
        },
        {
          name                       = "DenyAllInbound"
          priority                   = 4096
          direction                  = "Inbound"
          access                     = "Deny"
          protocol                   = "*"
          source_port_range          = "*"
          destination_port_range     = "*"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        },
      ]
    }

    (local.mgmt_subnet_key) = {
      address_prefix    = var.subnet_cidrs.mgmt
      service_endpoints = []
      nsg_rules = [
        {
          name                       = "AllowSSHInbound"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "22"
          source_address_prefix      = var.allowed_ssh_cidr
          destination_address_prefix = "*"
        },
        {
          name                       = "DenyAllInbound"
          priority                   = 4096
          direction                  = "Inbound"
          access                     = "Deny"
          protocol                   = "*"
          source_port_range          = "*"
          destination_port_range     = "*"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
        },
      ]
    }
  }
}
