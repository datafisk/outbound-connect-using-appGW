# DB System Outputs
output "db_system_id" {
  description = "OCID of the DB System"
  value       = oci_database_db_system.rac_db_system.id
}

output "db_system_state" {
  description = "Lifecycle state of the DB System"
  value       = oci_database_db_system.rac_db_system.state
}

output "db_system_shape" {
  description = "Shape of the DB System"
  value       = oci_database_db_system.rac_db_system.shape
}

# RAC Cluster Outputs
output "cluster_name" {
  description = "Name of the RAC cluster"
  value       = oci_database_db_system.rac_db_system.cluster_name
}

output "scan_dns_name" {
  description = "SCAN DNS name for the RAC cluster"
  value       = oci_database_db_system.rac_db_system.scan_dns_name
}

output "scan_dns_record_id" {
  description = "SCAN DNS record ID"
  value       = oci_database_db_system.rac_db_system.scan_dns_record_id
}

output "scan_ip_ids" {
  description = "List of SCAN IP OCIDs"
  value       = oci_database_db_system.rac_db_system.scan_ip_ids
}

output "vip_ids" {
  description = "List of VIP OCIDs for RAC nodes"
  value       = oci_database_db_system.rac_db_system.vip_ids
}

# Database Connection Information
output "database_connection_string" {
  description = "Database connection string (SCAN:port/service)"
  value       = format("%s:1521/%s", oci_database_db_system.rac_db_system.scan_dns_name, var.db_name)
}

output "pdb_connection_string" {
  description = "PDB connection string (SCAN:port/pdb_name)"
  value       = var.pdb_name != "" ? format("%s:1521/%s", oci_database_db_system.rac_db_system.scan_dns_name, var.pdb_name) : null
}

# Node Information
output "hostname_prefix" {
  description = "Hostname prefix for DB nodes"
  value       = oci_database_db_system.rac_db_system.hostname
}

output "domain" {
  description = "Domain name for the RAC cluster"
  value       = oci_database_db_system.rac_db_system.domain
}

output "listener_port" {
  description = "Oracle listener port"
  value       = oci_database_db_system.rac_db_system.listener_port
}

# Network Outputs
output "vcn_id" {
  description = "OCID of the VCN"
  value       = local.vcn_id
}

output "client_subnet_id" {
  description = "OCID of the client subnet"
  value       = local.client_subnet_id
}

output "backup_subnet_id" {
  description = "OCID of the backup subnet"
  value       = oci_core_subnet.rac_backup_subnet.id
}

# Database Home Information
output "db_home_id" {
  description = "OCID of the database home"
  value       = oci_database_db_system.rac_db_system.db_home[0].id
}

output "db_version" {
  description = "Oracle Database version"
  value       = oci_database_db_system.rac_db_system.version
}

# Storage Information
output "data_storage_size_gb" {
  description = "Total data storage size in GB"
  value       = oci_database_db_system.rac_db_system.data_storage_size_in_gb
}

output "storage_management" {
  description = "Storage management type (ASM or LVM)"
  value       = oci_database_db_system.rac_db_system.db_system_options[0].storage_management
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed RAC cluster"
  value = {
    db_system_id      = oci_database_db_system.rac_db_system.id
    cluster_name      = oci_database_db_system.rac_db_system.cluster_name
    scan_dns          = oci_database_db_system.rac_db_system.scan_dns_name
    connection_string = format("%s:1521/%s", oci_database_db_system.rac_db_system.scan_dns_name, var.db_name)
    pdb_connection    = var.pdb_name != "" ? format("%s:1521/%s", oci_database_db_system.rac_db_system.scan_dns_name, var.pdb_name) : null
    database_version  = oci_database_db_system.rac_db_system.version
    node_count        = var.node_count
    shape             = oci_database_db_system.rac_db_system.shape
    storage_gb        = oci_database_db_system.rac_db_system.data_storage_size_in_gb
    state             = oci_database_db_system.rac_db_system.state
  }
}

# Instructions
output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT
    Oracle RAC Cluster Deployed Successfully!

    Connection Information:
    - SCAN DNS: ${oci_database_db_system.rac_db_system.scan_dns_name}
    - Database: ${format("%s:1521/%s", oci_database_db_system.rac_db_system.scan_dns_name, var.db_name)}
    ${var.pdb_name != "" ? format("- PDB:      %s:1521/%s", oci_database_db_system.rac_db_system.scan_dns_name, var.pdb_name) : ""}

    Next Steps:
    1. Get node IPs: oci db node list --db-system-id ${oci_database_db_system.rac_db_system.id} --output table
    2. SSH to nodes: ssh -i <private-key> opc@<node-ip>
    3. Check cluster: sudo su - grid && crsctl status resource -t
    4. Check database: srvctl status database -d ${var.db_name}
    5. Configure XStream CDC for Confluent connector

    Documentation: See OCI-GETTING-STARTED.md for detailed instructions
  EOT
}
