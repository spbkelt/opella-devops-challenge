output "resource_group_name" {
  description = "Name of the environment resource group."
  value       = azurerm_resource_group.this.name
}

output "vnet_id" {
  description = "Resource ID of the Virtual Network."
  value       = module.vnet.vnet_id
}

output "vnet_name" {
  description = "Name of the Virtual Network."
  value       = module.vnet.vnet_name
}

output "subnet_ids" {
  description = "Map of subnet name → subnet resource ID."
  value       = module.vnet.subnet_ids
}

output "vm_name" {
  description = "Name of the Linux Virtual Machine."
  value       = azurerm_linux_virtual_machine.this.name
}

output "vm_private_ip" {
  description = "Private IP address of the VM NIC."
  value       = azurerm_network_interface.this.private_ip_address
}

output "vm_public_ip" {
  description = "Public IP address assigned to the VM (dev only)."
  value       = azurerm_public_ip.this.ip_address
}

output "storage_account_name" {
  description = "Name of the Storage Account."
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "Resource ID of the Storage Account."
  value       = azurerm_storage_account.this.id
}

output "storage_container_name" {
  description = "Name of the default blob container."
  value       = azurerm_storage_container.data.name
}
