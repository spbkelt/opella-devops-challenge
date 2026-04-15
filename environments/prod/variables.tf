variable "project" {
  description = "Short project identifier used in resource names and tags."
  type        = string
  default     = "opella"
}

variable "environment" {
  description = "Deployment environment (dev | staging | prod)."
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region for all resources in this environment."
  type        = string
  default     = "eastus"
}

variable "owner" {
  description = "Team or individual responsible for this environment. Used in the owner tag."
  type        = string
  default     = "platform-team"
}

variable "vnet_address_space" {
  description = "CIDR block for the Virtual Network."
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_ddos_protection" {
  description = "Enable Azure DDoS Network Protection on the VNET. Not recommended for dev due to cost."
  type        = bool
  default     = false
}

variable "enable_network_watcher" {
  description = "Deploy Network Watcher in this region. Set false if one already exists."
  type        = bool
  default     = true
}

variable "vm_size" {
  description = "Azure VM SKU for the Linux virtual machine."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "admin_username" {
  description = "Admin username for the Linux VM."
  type        = string
  default     = "azureuser"
}

variable "allowed_ssh_cidr" {
  description = "CIDR range allowed to SSH into the management subnet. Restrict to your office/VPN IP in real deployments."
  type        = string
  default     = "*"

  validation {
    condition     = can(cidrnetmask(var.allowed_ssh_cidr)) || var.allowed_ssh_cidr == "*"
    error_message = "allowed_ssh_cidr must be a valid CIDR block or '*'."
  }
}

variable "subnet_cidrs" {
  description = "CIDR ranges for application and management subnets."
  type = object({
    app  = string
    mgmt = string
  })

  validation {
    condition     = var.subnet_cidrs.app != var.subnet_cidrs.mgmt
    error_message = "app and mgmt subnet CIDRs must be different."
  }
}

variable "os_disk_storage_account_type" {
  description = "Storage account type for the OS disk (e.g. Standard_LRS, Premium_LRS)."
  type        = string
  default     = "Standard_LRS"
}

variable "storage_replication_type" {
  description = "Replication type for the storage account (LRS, ZRS, GRS, etc.)."
  type        = string
  default     = "LRS"
}

variable "storage_shared_access_key_enabled" {
  description = "Allow shared-key (SAS) access to the storage account. Disable in favour of RBAC in production."
  type        = bool
  default     = true
}

variable "vm_image_publisher" {
  description = "Publisher of the VM OS image."
  type        = string
  default     = "Canonical"
}

variable "vm_image_offer" {
  description = "Offer name of the VM OS image."
  type        = string
  default     = "0001-com-ubuntu-server-jammy"
}

variable "vm_image_sku" {
  description = "SKU of the VM OS image (e.g. 22_04-lts, 22_04-lts-gen2)."
  type        = string
  default     = "22_04-lts-gen2"
}

variable "os_disk_size_gb" {
  description = "Size of the OS disk in GB."
  type        = number
  default     = 30
}

variable "vm_image_version" {
  description = "Version of the VM OS image. Use 'latest' to always deploy the newest patch."
  type        = string
  default     = "latest"
}
