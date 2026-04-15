variable "resource_group_name" {
  description = "Name of the resource group in which to create the Virtual Network."
  type        = string
}

variable "location" {
  description = "Azure region where the Virtual Network will be deployed."
  type        = string
}

variable "vnet_name" {
  description = "Name of the Virtual Network."
  type        = string
}

variable "address_space" {
  description = "List of CIDR blocks assigned to the Virtual Network address space."
  type        = list(string)

  validation {
    condition     = length(var.address_space) > 0
    error_message = "address_space must contain at least one CIDR block."
  }
}

variable "dns_servers" {
  description = "Custom DNS server IP addresses. Leave empty to use Azure-provided DNS."
  type        = list(string)
  default     = []
}

variable "subnets" {
  description = <<-EOT
    Map of subnets to create. The map key becomes the subnet name.

    Each entry supports:
    - address_prefix    (required) CIDR block for the subnet.
    - service_endpoints (optional) Service endpoint identifiers (e.g. ["Microsoft.Storage"]).
    - nsg_rules         (optional) Inline NSG security rules; an NSG is created per subnet.
  EOT
  type = map(object({
    address_prefix    = string
    service_endpoints = optional(list(string), [])
    nsg_rules = optional(list(object({
      name                       = string
      priority                   = number
      direction                  = string
      access                     = string
      protocol                   = string
      source_port_range          = string
      destination_port_range     = string
      source_address_prefix      = string
      destination_address_prefix = string
    })), [])
  }))
  default = {}
}

variable "enable_ddos_protection" {
  description = "Attach an Azure DDoS Network Protection plan to the VNET. Incurs additional cost; recommended for production workloads."
  type        = bool
  default     = false
}

variable "enable_network_watcher" {
  description = "Deploy an Azure Network Watcher resource in the target region."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Map of tags applied to every resource created by this module."
  type        = map(string)
  default     = {}
}
