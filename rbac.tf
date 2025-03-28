resource "azurerm_role_assignment" "admin-user" {
  for_each             = var.deploy_entra_extension && var.os_flavor == "linux" ? { for key, value in var.rbac_config : key => value } : {}
  scope                = each.value.scope
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
}
