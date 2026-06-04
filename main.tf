# Oracle RAC on OCI - Root Module
# Uses existing VCN and subnet in peter-g compartment

terraform {
  required_version = ">= 1.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.67"
    }
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 1.0"
    }
  }
}

# OCI Provider - uses ~/.oci/config [DEFAULT] profile
provider "oci" {
  region = "us-phoenix-1"
}

# Oracle RAC Module
module "oracle_rac" {
  source = "./modules/oci-oracle-rac"

  # Compartment and AD
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain

  # Existing Network Resources
  use_existing_vcn           = var.use_existing_vcn
  existing_vcn_id            = var.existing_vcn_id
  use_existing_client_subnet = var.use_existing_client_subnet
  existing_client_subnet_id  = var.existing_client_subnet_id

  # Network Configuration
  backup_subnet_cidr = var.backup_subnet_cidr

  # Resource Naming
  name_prefix     = var.name_prefix
  cluster_name    = var.cluster_name
  hostname_prefix = var.hostname_prefix

  # Database System Configuration
  db_system_shape      = var.db_system_shape
  cpu_core_count       = var.cpu_core_count
  data_storage_size_gb = var.data_storage_size_gb
  db_edition           = var.db_edition

  # Database Configuration
  db_admin_password = var.db_admin_password
  db_name           = var.db_name
  pdb_name          = var.pdb_name
  db_version        = var.db_version
  db_workload       = var.db_workload

  # SSH Access
  ssh_public_key = var.ssh_public_key

  # License
  license_model = var.license_model

  # Backups
  auto_backup_enabled     = var.auto_backup_enabled
  auto_backup_window      = var.auto_backup_window
  recovery_window_in_days = var.recovery_window_in_days

  # Tags
  tags = var.tags
}

# Outputs
output "db_system_id" {
  description = "OCID of the Oracle RAC DB System"
  value       = module.oracle_rac.db_system_id
}

output "scan_dns_name" {
  description = "SCAN DNS name for RAC cluster connections"
  value       = module.oracle_rac.scan_dns_name
}

output "connection_string" {
  description = "Database connection string"
  value       = module.oracle_rac.database_connection_string
}

output "pdb_connection_string" {
  description = "PDB connection string"
  value       = module.oracle_rac.pdb_connection_string
}

output "deployment_summary" {
  description = "Deployment summary"
  value       = module.oracle_rac.deployment_summary
}

output "next_steps" {
  description = "Next steps after deployment"
  value       = module.oracle_rac.next_steps
}
