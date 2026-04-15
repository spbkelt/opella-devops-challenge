# -----------------------------------------------------------------------------
# DDoS Network Protection Plan (optional)
# Standard tier – attach to the VNET to enable L3/L4 volumetric protection.
# -----------------------------------------------------------------------------
resource "azurerm_network_ddos_protection_plan" "this" {
  count               = var.enable_ddos_protection ? 1 : 0
  name                = "${var.vnet_name}-ddos"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# Virtual Network
# -----------------------------------------------------------------------------
resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  dns_servers         = length(var.dns_servers) > 0 ? var.dns_servers : null

  dynamic "ddos_protection_plan" {
    for_each = var.enable_ddos_protection ? [1] : []
    content {
      id     = azurerm_network_ddos_protection_plan.this[0].id
      enable = true
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Network Security Groups — one per subnet
# Rules are provided inline via the subnets variable; each subnet always gets
# its own NSG so traffic is controlled at the subnet boundary by default.
# -----------------------------------------------------------------------------
resource "azurerm_network_security_group" "this" {
  for_each            = var.subnets
  name                = "nsg-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  dynamic "security_rule" {
    for_each = each.value.nsg_rules
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      source_port_range          = security_rule.value.source_port_range
      destination_port_range     = security_rule.value.destination_port_range
      source_address_prefix      = security_rule.value.source_address_prefix
      destination_address_prefix = security_rule.value.destination_address_prefix
    }
  }
}

# -----------------------------------------------------------------------------
# Subnets
# -----------------------------------------------------------------------------
resource "azurerm_subnet" "this" {
  for_each             = var.subnets
  name                 = each.key
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.address_prefix]
  service_endpoints    = each.value.service_endpoints
}

# -----------------------------------------------------------------------------
# NSG ↔ Subnet Associations
# -----------------------------------------------------------------------------
resource "azurerm_subnet_network_security_group_association" "this" {
  for_each                  = var.subnets
  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

# -----------------------------------------------------------------------------
# Network Watcher (optional)
# Only one Network Watcher may exist per region per subscription.
# Set enable_network_watcher = false when one already exists in the region.
# -----------------------------------------------------------------------------
resource "azurerm_network_watcher" "this" {
  count               = var.enable_network_watcher ? 1 : 0
  name                = "nw-${var.location}-001"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}
