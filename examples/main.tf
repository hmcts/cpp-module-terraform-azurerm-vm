provider "azurerm" {
  features {}
}
resource "azurerm_resource_group" "vm" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_subnet" "vm" {
  name                 = var.subnet_config.name
  resource_group_name  = var.subnet_config.resource_group_name
  virtual_network_name = var.subnet_config.virtual_network_name
  address_prefixes     = [var.subnet_config.address_prefixes]
}

data "azurerm_key_vault" "key_vault" {
  name                = var.key_vault_config.name
  resource_group_name = var.key_vault_config.resource_group_name
}

module "virtual-machine" {
  source = "../"

  # Resource Group, location, VNet and Subnet details
  resource_group_name     = azurerm_resource_group.vm.name
  location                = var.location
  virtual_network_name    = var.subnet_config.virtual_network_name
  virtual_network_rg_name = var.subnet_config.resource_group_name
  subnet_name             = azurerm_subnet.vm.name
  subnet_id               = azurerm_subnet.vm.id
  virtual_machine_name    = "vmlinux"

  # This module support multiple Pre-Defined Linux and Windows Distributions.
  # Check the README.md file for more pre-defined images for Ubuntu, Centos, RedHat.
  # Please make sure to use gen2 images supported VM sizes if you use gen2 distributions
  # Specify `disable_password_authentication = false` to create random admin password
  # Specify a valid password with `admin_password` argument to use your own password
  # To generate SSH key pair, specify `generate_admin_ssh_key = true`
  # To use existing key pair, specify `admin_ssh_key_data` to a valid SSH public key path.
  os_flavor               = "linux"
  linux_distribution_name = "ubuntu2004"
  virtual_machine_size    = "Standard_B2s"
  generate_admin_ssh_key  = true
  instances_count         = 1
  key_vault_id            = data.azurerm_key_vault.key_vault.id
  dns_zone_name           = "test"

  # Proxymity placement group, Availability Set and adding Public IP to VM's are optional.
  # remove these argument from module if you dont want to use it.
  enable_proximity_placement_group = false
  enable_vm_availability_set       = false
  enable_public_ip_address         = false

  # Boot diagnostics to troubleshoot virtual machines, by default uses managed
  # To use custom storage account, specify `storage_account_name` with a valid name
  # Passing a `null` value will utilize a Managed Storage Account to store Boot Diagnostics
  enable_boot_diagnostics = false

  # Attach a managed data disk to a Windows/Linux VM's. Possible Storage account type are:
  # `Standard_LRS`, `StandardSSD_ZRS`, `Premium_LRS`, `Premium_ZRS`, `StandardSSD_LRS`
  # or `UltraSSD_LRS` (UltraSSD_LRS only available in a region that support availability zones)
  # Initialize a new data disk - you need to connect to the VM and run diskmanagemnet or fdisk
  os_disk_name = "test"
  data_disks = [
    {
      name                 = "disk1"
      disk_size_gb         = 100
      storage_account_type = "StandardSSD_LRS"
    },
    {
      name                 = "disk2"
      disk_size_gb         = 200
      storage_account_type = "Standard_LRS"
    }
  ]
  deploy_log_analytics_agent = false
  tags = {
    ProjectName = "cpp-module-terraform-azurerm-vm"
    Env         = "lab"
  }
  depends_on = [azurerm_resource_group.vm, azurerm_subnet.vm]
}
