project     = "opella"
environment = "dev"
location    = "eastus"
owner       = "platform-team"

vnet_address_space     = "10.0.0.0/16"
enable_ddos_protection = false
enable_network_watcher = true

subnet_cidrs = {
  app  = "10.0.1.0/24"
  mgmt = "10.0.2.0/24"
}

admin_username = "azureuser"
# admin_ssh_public_key is not used in dev — a TLS key is generated automatically.

# Allow SSH from anywhere in dev. Tighten to your office/VPN IP for real deployments.
allowed_ssh_cidr = "*"

os_disk_storage_account_type = "Standard_LRS"

storage_replication_type          = "LRS"
storage_shared_access_key_enabled = true

vm_image_publisher = "Canonical"
vm_image_offer     = "0001-com-ubuntu-server-jammy"
vm_image_sku       = "22_04-lts-gen2"
vm_image_version   = "latest"
vm_size            = "Standard_DC1s_v3"
os_disk_size_gb    = 30

