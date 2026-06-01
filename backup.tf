resource "azurerm_backup_protected_vm" "vm" {
  count               = var.enable_backup ? var.instances_count : 0
  resource_group_name = var.rsv_resource_group_name
  recovery_vault_name = var.rsv_name
  source_vm_id        = var.os_flavor == "windows" ? azurerm_windows_virtual_machine.win_vm[count.index].id : azurerm_linux_virtual_machine.linux_vm[count.index].id
  backup_policy_id    = var.backup_policy_id
}
