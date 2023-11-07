variable "resource_group_location" {
  type        = string
  default     = "westeurope"
  description = "Location of the resource group."
}

variable "resource_group_name_prefix" {
  type        = string
  default     = "rg-testing"
  description = "Prefix of the resource group name that's combined with a random ID so name is unique in your Azure subscription."
}

variable "username" {
  type        = string
  description = "The username for the local account that will be created on the new VM."
  default     = "azureadmin"
}

variable "autokill_days" {
  type = string

  description = "The number of days after which the resource will be removed from Azure. Use the value 'never' if the resource shall not be deleted. Default is 1 day."
  default = "1"

  validation {
    condition = contains(["1", "3", "7", "14", "30", "never"], var.autokill_days)
    error_message = "Value should be any of ['1', '3', '7', '14', '30', 'never']."
  }
}

variable "autokill_reason" {
  type = string

  description = "An explanation for the autokill_days value. Why can the resource be deleted or not be deleted?"
  default = "testing"

  validation {
    condition = contains(["poc", "testing", "project"], var.autokill_reason)
    error_message = "Value should be any of ['poc', 'testing', 'project']."
  }
}

variable "project" {
  type = string
  default = "azure-vm-grafana-test"
}

variable "owner" {
  type = string
  default = "sgre@netlight.com"
}

variable "env" {
  type = string
  default = "dev"
}

variable "tags" {
  type = map(string)
  default = {}
}
