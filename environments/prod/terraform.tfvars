project     = "opella"
environment = "prod"
location    = "centralus"
owner       = "platform-team"

vnet_address_space = "10.1.0.0/16"

subnet_cidrs = {
  app  = "10.1.1.0/24"
  mgmt = "10.1.2.0/24"
}

enable_ddos_protection = true
enable_network_watcher = false

vm_size        = "Standard_D2s_v3"
admin_username = "azureuser"
# admin_ssh_public_key — supply via TF_VAR_admin_ssh_public_key or CI secret.

# Restrict to your corporate VPN or Bastion subnet CIDR.
# Example: allowed_ssh_cidr = "10.10.0.0/24"
allowed_ssh_cidr = "10.10.0.0/24"

os_disk_storage_account_type = "Premium_LRS"
os_disk_size_gb              = 64

storage_replication_type          = "ZRS"
storage_shared_access_key_enabled = true # Use Azure AD (RBAC) in production.

vm_image_publisher = "Canonical"
vm_image_offer     = "0001-com-ubuntu-server-jammy"
vm_image_sku       = "22_04-lts-gen2"
vm_image_version   = "latest"
