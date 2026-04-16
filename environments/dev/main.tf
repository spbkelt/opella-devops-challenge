# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "this" {
  name     = local.rg_name
  location = var.location
  tags     = local.common_tags
}

# -----------------------------------------------------------------------------
# Networking — reusable VNET module
# -----------------------------------------------------------------------------
module "vnet" {
  source = "../../modules/vnet"

  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  vnet_name              = local.vnet_name
  address_space          = [var.vnet_address_space]
  subnets                = local.subnets
  enable_ddos_protection = var.enable_ddos_protection
  enable_network_watcher = var.enable_network_watcher
  tags                   = local.common_tags
}

# -----------------------------------------------------------------------------
# Virtual Machine — Public IP
# Dev environment exposes a public IP for direct SSH access without a Bastion host.
# In production, use Azure Bastion or a VPN gateway instead.
# -----------------------------------------------------------------------------
resource "azurerm_public_ip" "this" {
  name                = local.pip_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# -----------------------------------------------------------------------------
# Virtual Machine — Network Interface
# Placed in the app subnet; associated public IP enables direct SSH from the
# allowed_ssh_cidr range via the management subnet NSG.
# -----------------------------------------------------------------------------
resource "azurerm_network_interface" "this" {
  #checkov:skip=CKV_AZURE_119:Public IP is intentional in dev for direct SSH access; use Bastion in prod.
  name                = local.nic_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "ipconfig-primary"
    subnet_id                     = module.vnet.subnet_ids[local.app_subnet_key]
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this.id
  }
}

# -----------------------------------------------------------------------------
# Virtual Machine — Ubuntu 22.04 LTS
# -----------------------------------------------------------------------------
resource "azurerm_linux_virtual_machine" "this" {
  #checkov:skip=CKV_AZURE_50:No VM extensions are deployed; check is a false positive.
  name                  = local.vm_name
  computer_name         = local.vm_computer_name
  resource_group_name   = azurerm_resource_group.this.name
  location              = azurerm_resource_group.this.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.this.id]
  tags                  = local.common_tags

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.vm_ssh.public_key_openssh
  }

  os_disk {
    name                 = local.os_disk_name
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_storage_account_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.vm_image_publisher
    offer     = var.vm_image_offer
    sku       = var.vm_image_sku
    version   = var.vm_image_version
  }
}

# -----------------------------------------------------------------------------
# Storage Account — blob storage for dev artifacts, scripts, and state data
#
# Network rules restrict access to the app subnet via a service endpoint,
# ensuring traffic stays on the Azure backbone rather than the public internet.
# -----------------------------------------------------------------------------
resource "tls_private_key" "vm_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "random_string" "storage_suffix" {
  length  = 5
  upper   = false
  special = false
  numeric = true
}
resource "azurerm_storage_account" "this" {
  #checkov:skip=CKV_AZURE_206:LRS replication is intentional in dev for cost savings.
  #checkov:skip=CKV2_AZURE_40:Shared key access is intentionally enabled in dev for developer convenience; public endpoint is required for CI runner data-plane access (see public_network_access_enabled comment).
  #checkov:skip=CKV_AZURE_33:Queue logging is implemented via azurerm_monitor_diagnostic_setting.storage_queue; azurerm 3.x does not expose queue_properties.logging for StorageV2.
  #checkov:skip=CKV2_AZURE_21:Blob read logging is implemented via azurerm_monitor_diagnostic_setting.storage_blob; azurerm 3.x does not expose blob_properties.logging for StorageV2.
  #checkov:skip=CKV2_AZURE_1:Customer Managed Key requires Key Vault integration; deferred as out-of-scope for this challenge.
  #checkov:skip=CKV2_AZURE_33:Private endpoint requires additional infrastructure; deferred as out-of-scope for this challenge.
  #checkov:skip=CKV_AZURE_35:Deny policy is enforced by azurerm_storage_account_network_rules after container creation; inline Allow is intentional to unblock the Terraform runner.
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"

  shared_access_key_enabled       = var.storage_shared_access_key_enabled
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  # See environments/prod/main.tf for why this must be true.
  public_network_access_enabled   = true
  allow_nested_items_to_be_public = false
  access_tier                     = "Hot"

  blob_properties {
    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  sas_policy {
    expiration_period = "00.08:00:00"
    expiration_action = "Log"
  }

  # See environments/prod/main.tf for the full explanation of this pattern.
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  lifecycle {
    ignore_changes = [network_rules]
  }

  tags = local.common_tags
}

# Network rules are applied after the container is created.
# See environments/prod/main.tf for the full explanation.
resource "azurerm_storage_account_network_rules" "this" {
  #checkov:skip=CKV_AZURE_59:Network rules are enforced; this resource applies Deny-by-default after container creation.
  storage_account_id         = azurerm_storage_account.this.id
  default_action             = "Deny"
  bypass                     = ["AzureServices"]
  virtual_network_subnet_ids = [module.vnet.subnet_ids[local.app_subnet_key]]
  ip_rules                   = var.storage_allowed_ip_rules

  depends_on = [azurerm_storage_container.data]
}

resource "azurerm_storage_container" "data" {
  #checkov:skip=CKV2_AZURE_21:Blob logging is configured on the parent storage account via blob_properties.logging.
  name                  = local.storage_container
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "law-opella-prod-eastus-001"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

resource "azurerm_monitor_diagnostic_setting" "storage_blob" {
  name                       = "diag-${azurerm_storage_account.this.name}-blob"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  metric {
    category = "Transaction"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "storage_queue" {
  name                       = "diag-${azurerm_storage_account.this.name}-queue"
  target_resource_id         = "${azurerm_storage_account.this.id}/queueServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  metric {
    category = "Transaction"
    enabled  = true
  }
}

