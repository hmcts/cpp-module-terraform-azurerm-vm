locals {
  backup_policy_by_criticality = {
    4 = "vm-crit4-5"
    5 = "vm-crit4-5"
  }
  backup_policy_name       = lookup(local.backup_policy_by_criticality, var.service_criticality, null)
  enable_backup_enrollment = local.backup_policy_name != null && var.rsv_name != null && var.rsv_resource_group_name != null
  backup_vm_count          = local.enable_backup_enrollment ? var.instances_count : 0
}

data "azurerm_client_config" "current" {}

resource "azurerm_backup_protected_vm" "main" {
  count               = local.backup_vm_count
  resource_group_name = var.rsv_resource_group_name
  recovery_vault_name = var.rsv_name
  source_vm_id        = var.os_flavor == "windows" ? azurerm_windows_virtual_machine.win_vm[count.index].id : azurerm_linux_virtual_machine.linux_vm[count.index].id
  backup_policy_id    = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.rsv_resource_group_name}/providers/Microsoft.RecoveryServices/vaults/${var.rsv_name}/backupPolicies/${local.backup_policy_name}"
}
