output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "public_ip_address" {
  value = azurerm_linux_virtual_machine.my_terraform_vm.public_ip_address
}

output "grafana_user_principal_name" {
  value = azuread_user.grafana_admin.user_principal_name
}

output "grafana_user_password" {
  value = nonsensitive(azuread_user.grafana_admin.password)
}

output "vm_admin_username" {
  value = var.username
}

output "vm_admin_ssh_key" {
  value = jsondecode(azapi_resource_action.ssh_public_key_gen.output).privateKey
}