# Module: azure/vnet

Reusable Terraform module that provisions an Azure Virtual Network with subnets,
per-subnet Network Security Groups, and optional DDoS protection and Network Watcher.

## Usage

```hcl
module "vnet" {
  source = "../../modules/vnet"

  resource_group_name = "rg-myapp-dev-eastus-001"
  location            = "eastus"
  vnet_name           = "vnet-myapp-dev-eastus-001"
  address_space       = ["10.0.0.0/16"]

  subnets = {
    "snet-app" = {
      address_prefix    = "10.0.1.0/24"
      service_endpoints = ["Microsoft.Storage"]
      nsg_rules = [
        {
          name                       = "AllowHTTPS"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "443"
          source_address_prefix      = "Internet"
          destination_address_prefix = "*"
        },
      ]
    }
  }

  tags = {
    environment = "dev"
    managed_by  = "terraform"
  }
}
```

## Design decisions

- **One NSG per subnet** — enforces the principle of least privilege at the subnet boundary. Each subnet's rules are co-located with the subnet definition for readability.
- **DDoS protection is opt-in** — the Standard plan carries a significant monthly cost (~$2,944/month for the plan itself). It is enabled only in production via `enable_ddos_protection = true`.
- **Network Watcher is opt-in** — only one Watcher per region per subscription is allowed. Set `enable_network_watcher = false` when a Watcher already exists in the target region to avoid conflicts.
- **Service endpoints** — enabling `Microsoft.Storage` on a subnet lets you lock the storage account network rules to that subnet without traversing the public internet.

## Inputs

<!-- BEGIN_TF_DOCS -->
| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| resource\_group\_name | Name of the resource group in which to create the Virtual Network. | `string` | n/a | yes |
| location | Azure region where the Virtual Network will be deployed. | `string` | n/a | yes |
| vnet\_name | Name of the Virtual Network. | `string` | n/a | yes |
| address\_space | List of CIDR blocks assigned to the Virtual Network address space. | `list(string)` | n/a | yes |
| dns\_servers | Custom DNS server IP addresses. Leave empty to use Azure-provided DNS. | `list(string)` | `[]` | no |
| subnets | Map of subnets to create. See variable description for object schema. | `map(object(...))` | `{}` | no |
| enable\_ddos\_protection | Attach an Azure DDoS Network Protection plan to the VNET. | `bool` | `false` | no |
| enable\_network\_watcher | Deploy an Azure Network Watcher resource in the target region. | `bool` | `false` | no |
| tags | Map of tags applied to every resource created by this module. | `map(string)` | `{}` | no |
<!-- END_TF_DOCS -->

## Outputs

<!-- BEGIN_TF_DOCS -->
| Name | Description |
|------|-------------|
| vnet\_id | Resource ID of the Virtual Network. |
| vnet\_name | Name of the Virtual Network. |
| vnet\_address\_space | Address space CIDRs assigned to the Virtual Network. |
| subnet\_ids | Map of subnet name → subnet resource ID. |
| subnet\_address\_prefixes | Map of subnet name → address prefix (CIDR). |
| nsg\_ids | Map of subnet name → Network Security Group resource ID. |
| ddos\_protection\_plan\_id | DDoS Protection Plan ID. Null if disabled. |
| network\_watcher\_id | Network Watcher ID. Null if disabled. |
<!-- END_TF_DOCS -->

## Generating documentation

This README is managed by [terraform-docs](https://terraform-docs.io/). To regenerate the
`BEGIN_TF_DOCS` / `END_TF_DOCS` sections in-place:

```bash
terraform-docs markdown table --output-file README.md --output-mode inject .
```
