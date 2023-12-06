resource_group_name = "RG-LAB-TF-TEST-VM-01"
location            = "uksouth"

subnet_config = {
  name                 = "SN-LAB-SBZ-01-test"
  resource_group_name  = "RG-LAB-INT-01"
  virtual_network_name = "VN-LAB-INT-01"
  address_prefixes     = "10.1.2.48/28"
}
