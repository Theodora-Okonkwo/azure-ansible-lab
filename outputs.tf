output "public_ips" {
  description = "Public IP addresses of all VMs"
  value       = [for vm in azurerm_linux_virtual_machine.main : vm.public_ip_address]
}

output "vm_roles_with_ips" {
  description = "Map of VM roles to their public IPs"
  value = {
    for i, vm in azurerm_linux_virtual_machine.main :
    var.vm_roles[i] => vm.public_ip_address
  }
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "ssh_command_examples" {
  description = "SSH commands to connect to each VM"
  value = [
    for vm in azurerm_linux_virtual_machine.main :
    "ssh ${var.admin_username}@${vm.public_ip_address}"
  ]
}