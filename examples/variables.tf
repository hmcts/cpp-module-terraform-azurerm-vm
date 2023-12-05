variable "resource_group_name" {
  type        = string
  default     = ""
  description = "description"
}

variable "location" {
  type        = string
  default     = ""
  description = "description"
}

variable "tags" {
  type = map(string)
}

variable "subnet_config" {
  type        = map(string)
  default     = {}
  description = "Subnet config"
}

variable "key_vault_config" {
  type        = map(string)
  default     = {}
  description = "Key vault config"
}

variable "vmss_config" {
  type        = map(string)
  default     = {}
  description = "VMSS config"
}
