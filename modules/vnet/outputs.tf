output "vnet_id" {
  description = "Resource ID of the Virtual Network."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the Virtual Network."
  value       = azurerm_virtual_network.this.name
}

output "vnet_address_space" {
  description = "Address space CIDRs assigned to the Virtual Network."
  value       = azurerm_virtual_network.this.address_space
}

output "subnet_ids" {
  description = "Map of subnet name → subnet resource ID."
  value       = { for k, v in azurerm_subnet.this : k => v.id }
}

output "subnet_address_prefixes" {
  description = "Map of subnet name → address prefix (CIDR)."
  value       = { for k, v in azurerm_subnet.this : k => v.address_prefixes[0] }
}

output "nsg_ids" {
  description = "Map of subnet name → Network Security Group resource ID."
  value       = { for k, v in azurerm_network_security_group.this : k => v.id }
}

output "ddos_protection_plan_id" {
  description = "Resource ID of the DDoS Protection Plan. Null when DDoS protection is disabled."
  value       = var.enable_ddos_protection ? azurerm_network_ddos_protection_plan.this[0].id : null
}

output "network_watcher_id" {
  description = "Resource ID of the Network Watcher. Null when Network Watcher deployment is disabled."
  value       = var.enable_network_watcher ? azurerm_network_watcher.this[0].id : null
}
