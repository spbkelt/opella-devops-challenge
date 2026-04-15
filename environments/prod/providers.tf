provider "azurerm" {
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
