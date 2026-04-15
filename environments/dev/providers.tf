provider "azurerm" {
  features {
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = false # dev: skip drain wait for faster teardown
      skip_shutdown_and_force_delete = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
