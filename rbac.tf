resource "azurerm_role_assignment" "admin-user" {
  count                = var.deploy_entra_extension && var.os_flavor == "linux" ? var.instances_count : 0
  scope                = azurerm_linux_virtual_machine.linux_vm[count.index].id
  role_definition_name = "Virtual Machine Administrator Login"
  principal_id         = var.admin_user_group_id
}

resource "azurerm_role_assignment" "standard-user" {
  count                = var.deploy_entra_extension && var.os_flavor == "linux" ? var.instances_count : 0
  scope                = azurerm_linux_virtual_machine.linux_vm[count.index].id
  role_definition_name = "Virtual Machine User Login"
  principal_id         = var.standard_user_group_id
}
