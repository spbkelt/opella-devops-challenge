provider "azurerm" {
  # Required when shared_access_key_enabled = false on any storage account.
  # Without this the provider polls the storage data plane with key auth after
  # creation, which is rejected with KeyBasedAuthenticationNotPermitted.
  storage_use_azuread = true

  features {
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = true # prod: allow in-flight requests to drain
      skip_shutdown_and_force_delete = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
