output "admin_ssh_key_public" {
  description = "The generated public key data in PEM format"
  value       = var.disable_password_authentication == true && var.generate_admin_ssh_key == true && var.os_flavor == "linux" ? tls_private_key.rsa[0].public_key_openssh : null
}

output "admin_ssh_key_private" {
  description = "The generated private key data in PEM format"
  sensitive   = true
  value       = var.disable_password_authentication == true && var.generate_admin_ssh_key == true && var.os_flavor == "linux" ? tls_private_key.rsa[0].private_key_pem : null
}

output "windows_vm_password" {
  description = "Password for the windows VM"
  sensitive   = true
  value       = var.admin_password == null ? element(concat(random_password.passwd.*.result, [""]), 0) : var.admin_password
}

output "linux_vm_password" {
  description = "Password for the Linux VM"
  sensitive   = true
  value       = var.disable_password_authentication == false && var.admin_password == null ? element(concat(random_password.passwd.*.result, [""]), 0) : var.admin_password
}

output "windows_vm_public_ips" {
  description = "Public IP's map for the all windows Virtual Machines"
  value       = var.enable_public_ip_address == true && var.os_flavor == "windows" ? zipmap(azurerm_windows_virtual_machine.win_vm.*.name, azurerm_windows_virtual_machine.win_vm.*.public_ip_address) : null
}

output "windows_vm_private_ips" {
  description = "Public IP's map for the all windows Virtual Machines"
  value       = var.os_flavor == "windows" ? zipmap(azurerm_windows_virtual_machine.win_vm.*.name, azurerm_windows_virtual_machine.win_vm.*.private_ip_address) : null
}

output "linux_vm_public_ips" {
  description = "Public IP's map for the all windows Virtual Machines"
  value       = var.enable_public_ip_address == true && var.os_flavor == "linux" ? zipmap(azurerm_linux_virtual_machine.linux_vm.*.name, azurerm_linux_virtual_machine.linux_vm.*.public_ip_address) : null
}

output "linux_vm_private_ips" {
  description = "Public IP's map for the all windows Virtual Machines"
  value       = var.os_flavor == "linux" ? zipmap(azurerm_linux_virtual_machine.linux_vm.*.name, azurerm_linux_virtual_machine.linux_vm.*.private_ip_address) : null
}

output "linux_virtual_machine_ids" {
  description = "The resource id's of all Linux Virtual Machine."
  value       = var.os_flavor == "linux" ? concat(azurerm_linux_virtual_machine.linux_vm.*.id, [""]) : null
}

output "linux_virtual_machine_names" {
  description = "The resource id's of all Linux Virtual Machine."
  value       = var.os_flavor == "linux" ? concat(azurerm_linux_virtual_machine.linux_vm.*.name, [""]) : null
}

output "windows_virtual_machine_ids" {
  description = "The resource id's of all Windows Virtual Machine."
  value       = var.os_flavor == "windows" ? concat(azurerm_windows_virtual_machine.win_vm.*.id, [""]) : null
}

output "vm_availability_set_id" {
  description = "The resource ID of Virtual Machine availability set"
  value       = var.enable_vm_availability_set == true ? element(concat(azurerm_availability_set.aset.*.id, [""]), 0) : null
}

output "linux_vm_system_assigned_identity_principal_ids" {
  description = "System assigned identity principal IDs for Linux VMs"
  value = var.os_flavor == "linux" && contains(["SystemAssigned", "SystemAssigned, UserAssigned"], var.managed_identity_type) ? [
    for vm in azurerm_linux_virtual_machine.linux_vm : try(vm.identity[0].principal_id, null)
  ] : null
}

output "windows_vm_system_assigned_identity_principal_ids" {
  description = "System assigned identity principal IDs for Windows VMs"
  value = var.os_flavor == "windows" && contains(["SystemAssigned", "SystemAssigned, UserAssigned"], var.managed_identity_type) ? [
    for vm in azurerm_windows_virtual_machine.win_vm : try(vm.identity[0].principal_id, null)
  ] : null
}
