output "oracle_private_ip" {
  description = "Private IP address of Oracle VM"
  value       = azurerm_network_interface.oracle.private_ip_address
}

output "oracle_public_ip" {
  description = "Public IP address of Oracle VM (if created)"
  value       = var.create_public_ip ? azurerm_public_ip.oracle[0].ip_address : null
}

output "oracle_vm_id" {
  description = "ID of the Oracle VM"
  value       = azurerm_linux_virtual_machine.oracle.id
}

output "oracle_connection_string" {
  description = "Oracle connection string for XStream connector"
  value       = "jdbc:oracle:thin:@${azurerm_network_interface.oracle.private_ip_address}:1521/${var.oracle_pdb_name}"
}

output "oracle_hostname" {
  description = "Oracle hostname for connector configuration"
  value       = azurerm_network_interface.oracle.private_ip_address
}

output "oracle_port" {
  description = "Oracle database port"
  value       = 1521
}

output "oracle_pdb_name" {
  description = "Oracle PDB name"
  value       = var.oracle_pdb_name
}

output "oracle_xstream_user" {
  description = "Oracle XStream CDC user"
  value       = "C##GGADMIN"
}

output "ssh_command" {
  description = "SSH command to connect to Oracle VM"
  value       = var.create_public_ip ? "ssh ${var.admin_username}@${azurerm_public_ip.oracle[0].ip_address}" : "ssh ${var.admin_username}@${azurerm_network_interface.oracle.private_ip_address}"
}
