locals {
  vm_details = flatten([
    for k, inst in azurerm_linux_virtual_machine.linux_vm : [
      {
        vmname = var.dns_zone_name != "" ? replace(inst.name, ".${var.dns_zone_name}", "") : inst.name
        vmid   = inst.id
      }
    ]
  ])
  vm_data_disks = flatten([
    for vm in local.vm_details : [
      for idx, disk in var.data_disks : {
        vmname    = vm.vmname
        vmid      = vm.vmid
        idx       = idx
        data_disk = disk
      }
    ]
  ])
}

#---------------------------------------------------------------
# Generates SSH2 key Pair for Linux VM's (Dev Environment only)
#---------------------------------------------------------------
resource "tls_private_key" "rsa" {
  count     = var.generate_admin_ssh_key ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

#----------------------------------------------------------
# Resource Group, VNet, Subnet selection & Random Resources
#----------------------------------------------------------
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

data "azurerm_resource_group" "sa_rg" {
  count = var.storage_account_name != null ? 1 : 0
  name  = var.storage_account_rg
}

data "azurerm_virtual_network" "vnet" {
  name                = var.virtual_network_name
  resource_group_name = var.virtual_network_rg_name
}

data "azurerm_subnet" "snet" {
  name                 = var.subnet_name
  virtual_network_name = var.virtual_network_name
  resource_group_name  = var.virtual_network_rg_name
}

data "azurerm_storage_account" "storeacc" {
  count               = var.storage_account_name != null ? 1 : 0
  name                = var.storage_account_name
  resource_group_name = data.azurerm_resource_group.sa_rg[0].name
}

resource "random_password" "passwd" {
  count       = (var.os_flavor == "linux" && var.disable_password_authentication == false && var.admin_password == null ? 1 : (var.os_flavor == "windows" && var.admin_password == null ? 1 : 0))
  length      = var.random_password_length
  min_upper   = 4
  min_lower   = 2
  min_numeric = 4
  special     = false

  keepers = {
    admin_password = var.virtual_machine_name
  }
}

# Write to key vault
resource "azurerm_key_vault_secret" "ssh_public_key" {
  count        = var.generate_admin_ssh_key == true ? 1 : 0
  name         = "${var.virtual_machine_name}-ssh-public-key"
  value        = tls_private_key.rsa[0].public_key_openssh
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "ssh_private_key" {
  count        = var.generate_admin_ssh_key == true ? 1 : 0
  name         = "${var.virtual_machine_name}--vmss-ssh-private-key"
  value        = tls_private_key.rsa[0].private_key_pem
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "password" {
  count        = var.disable_password_authentication != true && var.admin_password == null ? 1 : 0
  name         = "${var.virtual_machine_name}--vmss-admin-password"
  value        = random_password.passwd[0].result
  key_vault_id = var.key_vault_id
}

#-----------------------------------
# Public IP for Virtual Machine
#-----------------------------------
resource "azurerm_public_ip" "pip" {
  count               = var.enable_public_ip_address == true ? var.instances_count : 0
  name                = upper("pip-vm-${var.virtual_machine_name}-${data.azurerm_resource_group.rg.location}-0${count.index + 1}")
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = var.public_ip_allocation_method
  sku                 = var.public_ip_sku
  sku_tier            = var.public_ip_sku_tier
  domain_name_label   = var.domain_name_label
  zones               = var.public_ip_availability_zone
  tags                = merge({ "ResourceName" = upper("pip-vm-${var.virtual_machine_name}-${data.azurerm_resource_group.rg.location}-0${count.index + 1}") }, var.tags, )

  lifecycle {
    ignore_changes = [
      tags,
      ip_tags,
    ]
  }
}

#---------------------------------------
# Network Interface for Virtual Machine
#---------------------------------------
resource "azurerm_network_interface" "nic" {
  count                         = var.instances_count
  name                          = upper("nic-vm${var.virtual_machine_name}${format("%02d", count.index + 1)}")
  resource_group_name           = var.resource_group_name
  location                      = var.location
  dns_servers                   = var.dns_servers
  enable_ip_forwarding          = var.enable_ip_forwarding
  enable_accelerated_networking = var.enable_accelerated_networking
  internal_dns_name_label       = var.internal_dns_name_label
  tags                          = merge({ "ResourceName" = upper("nic-vm${var.virtual_machine_name}${format("%02d", count.index + 1)}") }, var.tags, )

  ip_configuration {
    name                          = upper("ipconfig-${var.virtual_machine_name}${format("%02d", count.index + 1)}")
    primary                       = true
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = var.private_ip_address_allocation_type
    private_ip_address            = var.private_ip_address_allocation_type == "Static" ? element(concat(var.private_ip_address, [""]), count.index) : null
    public_ip_address_id          = var.enable_public_ip_address == true ? element(concat(azurerm_public_ip.pip.*.id, [""]), count.index) : null
  }

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

#----------------------------------------------------------------------------------------------------
# Proximity placement group for virtual machines, virtual machine scale sets and availability sets.
#----------------------------------------------------------------------------------------------------
resource "azurerm_proximity_placement_group" "appgrp" {
  count               = var.enable_proximity_placement_group ? 1 : 0
  name                = upper("proxigrp-${var.virtual_machine_name}-${data.azurerm_resource_group.rg.location}")
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  tags                = merge({ "ResourceName" = upper("proxigrp-${var.virtual_machine_name}-${data.azurerm_resource_group.rg.location}") }, var.tags, )

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

#-----------------------------------------------------
# Manages an Availability Set for Virtual Machines.
#-----------------------------------------------------
resource "azurerm_availability_set" "aset" {
  count                        = var.enable_vm_availability_set ? 1 : 0
  name                         = upper("AS-${var.virtual_machine_name}-${var.location}")
  resource_group_name          = var.resource_group_name
  location                     = var.location
  platform_fault_domain_count  = var.platform_fault_domain_count
  platform_update_domain_count = var.platform_update_domain_count
  proximity_placement_group_id = var.enable_proximity_placement_group ? azurerm_proximity_placement_group.appgrp.0.id : null
  managed                      = true
  tags                         = merge({ "ResourceName" = upper("AS-${var.virtual_machine_name}-${data.azurerm_resource_group.rg.location}") }, var.tags, )

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

#---------------------------------------
# Linux Virutal machine
#---------------------------------------
resource "azurerm_linux_virtual_machine" "linux_vm" {
  count                           = var.os_flavor == "linux" ? var.instances_count : 0
  name                            = var.append_dns_name ? format("%s%02d.%s", upper(var.virtual_machine_name), count.index + 1, var.dns_zone_name) : format("%s%02d", upper(var.virtual_machine_name), count.index + 1)
  resource_group_name             = var.resource_group_name
  location                        = var.location
  size                            = var.virtual_machine_size
  admin_username                  = var.admin_username
  admin_password                  = var.disable_password_authentication == false && var.admin_password == null ? element(concat(random_password.passwd.*.result, [""]), 0) : var.admin_password
  disable_password_authentication = var.disable_password_authentication
  network_interface_ids           = [element(concat(azurerm_network_interface.nic.*.id, [""]), count.index)]
  source_image_id                 = var.source_image_id != null ? var.source_image_id : null
  provision_vm_agent              = true
  allow_extension_operations      = true
  dedicated_host_id               = var.dedicated_host_id
  custom_data                     = var.custom_data != null ? var.custom_data : null
  availability_set_id             = var.enable_vm_availability_set == true ? element(concat(azurerm_availability_set.aset.*.id, [""]), 0) : null
  encryption_at_host_enabled      = var.enable_encryption_at_host
  proximity_placement_group_id    = var.enable_proximity_placement_group ? azurerm_proximity_placement_group.appgrp.0.id : null
  zone                            = var.vm_availability_zone

  tags = merge(
    {
      "ResourceName" = format("%s%02d", var.virtual_machine_name, count.index + 1)
    },
    var.tags
  )

  dynamic "admin_ssh_key" {
    for_each = var.disable_password_authentication ? [1] : []
    content {
      username   = var.admin_username
      public_key = var.admin_ssh_key_data == null ? tls_private_key.rsa[0].public_key_openssh : file(var.admin_ssh_key_data)
    }
  }

  dynamic "source_image_reference" {
    for_each = var.source_image_id != null ? [] : [1]
    content {
      publisher = var.custom_image != null ? var.custom_image["publisher"] : var.linux_distribution_list[lower(var.linux_distribution_name)]["publisher"]
      offer     = var.custom_image != null ? var.custom_image["offer"] : var.linux_distribution_list[lower(var.linux_distribution_name)]["offer"]
      sku       = var.custom_image != null ? var.custom_image["sku"] : var.linux_distribution_list[lower(var.linux_distribution_name)]["sku"]
      version   = var.custom_image != null ? var.custom_image["version"] : var.linux_distribution_list[lower(var.linux_distribution_name)]["version"]
    }
  }
  dynamic "plan" {
    for_each = var.require_plan != null ? [] : [1]
    content {
      name      = var.custom_image != null ? var.custom_image["sku"] : var.linux_distribution_list[lower(var.linux_distribution_name)]["sku"]
      product   = var.custom_image != null ? var.custom_image["offer"] : var.linux_distribution_list[lower(var.linux_distribution_name)]["offer"]
      publisher = var.custom_image != null ? var.custom_image["publisher"] : var.linux_distribution_list[lower(var.linux_distribution_name)]["publisher"]
    }
  }

  os_disk {
    storage_account_type      = var.os_disk_storage_account_type
    caching                   = var.os_disk_caching
    disk_encryption_set_id    = var.disk_encryption_set_id
    disk_size_gb              = var.disk_size_gb
    write_accelerator_enabled = var.enable_os_disk_write_accelerator
    name                      = length(var.custom-os-disk-name) > 0 ? var.custom-os-disk-name[count.index] : "${var.os_disk_name}-${count.index}"
  }

  additional_capabilities {
    ultra_ssd_enabled = var.enable_ultra_ssd_data_disk_storage_support
  }

  dynamic "identity" {
    for_each = var.managed_identity_type != null ? [1] : []
    content {
      type         = var.managed_identity_type
      identity_ids = var.managed_identity_type == "UserAssigned" || var.managed_identity_type == "SystemAssigned, UserAssigned" ? var.managed_identity_ids : null
    }
  }

  dynamic "boot_diagnostics" {
    for_each = var.enable_boot_diagnostics ? [1] : []
    content {
      storage_account_uri = var.storage_account_name != null ? data.azurerm_storage_account.storeacc.0.primary_blob_endpoint : var.storage_account_uri
    }
  }

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

#---------------------------------------
# Windows Virutal machine
#---------------------------------------
resource "azurerm_windows_virtual_machine" "win_vm" {
  count                        = var.os_flavor == "windows" ? var.instances_count : 0
  name                         = var.append_dns_name ? format("%s%02d.%s", upper(var.virtual_machine_name), count.index + 1, var.dns_zone_name) : format("%s%02d", upper(var.virtual_machine_name), count.index + 1)
  computer_name                = var.append_dns_name ? format("%s%02d.%s", upper(var.virtual_machine_name), count.index + 1, var.dns_zone_name) : format("%s%02d", upper(var.virtual_machine_name), count.index + 1)
  resource_group_name          = data.azurerm_resource_group.rg.name
  location                     = data.azurerm_resource_group.rg.location
  size                         = var.virtual_machine_size
  admin_username               = var.admin_username
  admin_password               = var.admin_password == null ? element(concat(random_password.passwd.*.result, [""]), 0) : var.admin_password
  network_interface_ids        = [element(concat(azurerm_network_interface.nic.*.id, [""]), count.index)]
  source_image_id              = var.source_image_id != null ? var.source_image_id : null
  provision_vm_agent           = true
  allow_extension_operations   = true
  dedicated_host_id            = var.dedicated_host_id
  custom_data                  = var.custom_data != null ? var.custom_data : null
  enable_automatic_updates     = var.enable_automatic_updates
  license_type                 = var.license_type
  availability_set_id          = var.enable_vm_availability_set == true ? element(concat(azurerm_availability_set.aset.*.id, [""]), 0) : null
  encryption_at_host_enabled   = var.enable_encryption_at_host
  proximity_placement_group_id = var.enable_proximity_placement_group ? azurerm_proximity_placement_group.appgrp.0.id : null
  patch_mode                   = var.patch_mode
  zone                         = var.vm_availability_zone
  timezone                     = var.vm_time_zone

  tags = merge(
    {
      "ResourceName" = format("%s%02d", var.virtual_machine_name, count.index + 1)
    },
    var.tags
  )

  dynamic "source_image_reference" {
    for_each = var.source_image_id != null ? [] : [1]
    content {
      publisher = var.custom_image != null ? var.custom_image["publisher"] : var.windows_distribution_list[lower(var.windows_distribution_name)]["publisher"]
      offer     = var.custom_image != null ? var.custom_image["offer"] : var.windows_distribution_list[lower(var.windows_distribution_name)]["offer"]
      sku       = var.custom_image != null ? var.custom_image["sku"] : var.windows_distribution_list[lower(var.windows_distribution_name)]["sku"]
      version   = var.custom_image != null ? var.custom_image["version"] : var.windows_distribution_list[lower(var.windows_distribution_name)]["version"]
    }
  }

  os_disk {
    storage_account_type      = var.os_disk_storage_account_type
    caching                   = var.os_disk_caching
    disk_encryption_set_id    = var.disk_encryption_set_id
    disk_size_gb              = var.disk_size_gb
    write_accelerator_enabled = var.enable_os_disk_write_accelerator
    name                      = var.os_disk_name
  }

  additional_capabilities {
    ultra_ssd_enabled = var.enable_ultra_ssd_data_disk_storage_support
  }

  dynamic "identity" {
    for_each = var.managed_identity_type != null ? [1] : []
    content {
      type         = var.managed_identity_type
      identity_ids = var.managed_identity_type == "UserAssigned" || var.managed_identity_type == "SystemAssigned, UserAssigned" ? var.managed_identity_ids : null
    }
  }

  dynamic "winrm_listener" {
    for_each = var.winrm_protocol != null ? [1] : []
    content {
      protocol        = var.winrm_protocol
      certificate_url = var.winrm_protocol == "Https" ? var.key_vault_certificate_secret_url : null
    }
  }

  dynamic "additional_unattend_content" {
    for_each = var.additional_unattend_content != null ? [1] : []
    content {
      content = var.additional_unattend_content
      setting = var.additional_unattend_content_setting
    }
  }

  dynamic "boot_diagnostics" {
    for_each = var.enable_boot_diagnostics ? [1] : []
    content {
      storage_account_uri = var.storage_account_name != null ? data.azurerm_storage_account.storeacc.0.primary_blob_endpoint : var.storage_account_uri
    }
  }

  lifecycle {
    ignore_changes = [
      tags,
      patch_mode,
    ]
  }
}

#---------------------------------------
# Virtual machine data disks
#---------------------------------------
resource "azurerm_managed_disk" "data_disk" {
  for_each             = { for obj in local.vm_data_disks : "${obj.vmname}_${obj.idx}" => obj }
  name                 = "${each.value.vmname}_DataDisk_${each.value.idx}"
  resource_group_name  = var.resource_group_name
  location             = var.location
  storage_account_type = lookup(each.value.data_disk, "storage_account_type", "StandardSSD_LRS")
  create_option        = "Empty"
  disk_size_gb         = each.value.data_disk.disk_size_gb
  tags                 = merge({ "ResourceName" = "${var.virtual_machine_name}_DataDisk_${each.value.idx}" }, var.tags, )

  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "data_disk" {
  for_each           = { for obj in local.vm_data_disks : "${obj.vmname}_${obj.idx}" => obj }
  managed_disk_id    = azurerm_managed_disk.data_disk["${each.value.vmname}_${each.value.idx}"].id
  virtual_machine_id = var.os_flavor == "windows" ? azurerm_windows_virtual_machine.win_vm[0].id : each.value.vmid
  lun                = each.value.idx
  caching            = "ReadWrite"
}


#--------------------------------------------------------------
# Azure Log Analytics Workspace Agent Installation for windows
#--------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "omsagentwin" {
  count                      = var.deploy_log_analytics_agent && var.log_analytics_workspace_id != null && var.os_flavor == "windows" ? var.instances_count : 0
  name                       = var.instances_count == 1 ? "OmsAgentForWindows" : format("%s%s", "OmsAgentForWindows", count.index + 1)
  virtual_machine_id         = azurerm_windows_virtual_machine.win_vm[count.index].id
  publisher                  = "Microsoft.EnterpriseCloud.Monitoring"
  type                       = "MicrosoftMonitoringAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true

  settings = <<SETTINGS
    {
      "workspaceId": "${var.log_analytics_customer_id}"
    }
  SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
    {
    "workspaceKey": "${var.log_analytics_workspace_primary_shared_key}"
    }
  PROTECTED_SETTINGS
}

#--------------------------------------------------------------
# Azure Log Analytics Workspace Agent Installation for Linux
#--------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "omsagentlinux" {
  count                      = var.deploy_log_analytics_agent && var.log_analytics_workspace_id != null && var.os_flavor == "linux" ? var.instances_count : 0
  name                       = var.instances_count == 1 ? "OmsAgentForLinux" : format("%s%s", "OmsAgentForLinux", count.index + 1)
  virtual_machine_id         = azurerm_linux_virtual_machine.linux_vm[count.index].id
  publisher                  = "Microsoft.EnterpriseCloud.Monitoring"
  type                       = "OmsAgentForLinux"
  type_handler_version       = "1.13"
  auto_upgrade_minor_version = true

  settings = <<SETTINGS
    {
      "workspaceId": "${var.log_analytics_customer_id}"
    }
  SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
    {
    "workspaceKey": "${var.log_analytics_workspace_primary_shared_key}"
    }
  PROTECTED_SETTINGS
}


#--------------------------------------
# azurerm monitoring diagnostics
#--------------------------------------
resource "azurerm_monitor_diagnostic_setting" "vmdiag" {
  count                      = var.log_analytics_workspace_id != null || var.storage_account_name != null ? var.instances_count : 0
  name                       = upper("DIAG-${var.virtual_machine_name}${format("%02d", count.index + 1)}")
  target_resource_id         = azurerm_linux_virtual_machine.linux_vm[count.index].id
  storage_account_id         = var.storage_account_name != null ? data.azurerm_storage_account.storeacc.0.id : null
  log_analytics_workspace_id = var.log_analytics_workspace_id

  metric {
    category = "AllMetrics"

    retention_policy {
      enabled = false
    }
  }
}

#--------------------------------------------------------------
# AADSSHLoginForLinux for Linux extension
#--------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "entra" {
  count                      = var.deploy_entra_extension && var.os_flavor == "linux" ? var.instances_count : 0
  name                       = var.instances_count == 1 ? "AADSSHLoginForLinux" : format("%s%s", "AADSSHLoginForLinux", count.index + 1)
  virtual_machine_id         = azurerm_linux_virtual_machine.linux_vm[count.index].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADSSHLoginForLinux"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
}
