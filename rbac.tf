resource "azurerm_role_assignment" "admin-user" {
  count                = var.deploy_entra_extension && var.os_flavor == "linux" && var.admin_user_group_id != null ? 1 : 0
  scope                = data.azurerm_resource_group.rg.id
  role_definition_name = "Virtual Machine Administrator Login"
  principal_id         = var.admin_user_group_id
}

resource "azurerm_role_assignment" "standard-user" {
  count                = var.deploy_entra_extension && var.os_flavor == "linux" && var.standard_user_group_id != null ? 1 : 0
  scope                = data.azurerm_resource_group.rg.id
  role_definition_name = "Virtual Machine User Login"
  principal_id         = var.standard_user_group_id
}
