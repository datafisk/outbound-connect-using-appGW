# Oracle Database System with 2-Node RAC
resource "oci_database_db_system" "rac_db_system" {
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain

  # RAC Cluster Configuration
  database_edition = var.db_edition
  db_system_options {
    storage_management = var.storage_management # ASM for RAC
  }

  # Cluster Name and Node Count
  cluster_name = var.cluster_name
  node_count   = var.node_count # 2 for Base DB Service RAC

  # VM Shape and Resources
  shape          = var.db_system_shape
  cpu_core_count = var.cpu_core_count

  # Storage Configuration
  data_storage_size_in_gb = var.data_storage_size_gb

  # Network Configuration
  subnet_id = local.client_subnet_id
  # backup_subnet_id not supported for VM shapes (only for bare metal)
  hostname = var.hostname_prefix

  # SSH Access
  ssh_public_keys = [var.ssh_public_key]

  # Database Home and Database Configuration
  db_home {
    database {
      admin_password = var.db_admin_password
      db_name        = var.db_name
      pdb_name       = var.pdb_name

      # Database Workload
      db_workload = var.db_workload

      # Character Sets
      character_set  = var.character_set
      ncharacter_set = var.ncharacter_set

      # Database Backup Configuration
      db_backup_config {
        auto_backup_enabled     = var.auto_backup_enabled
        auto_backup_window      = var.auto_backup_window
        recovery_window_in_days = var.recovery_window_in_days
      }
    }

    # Database Version
    db_version   = var.db_version
    display_name = "${var.name_prefix}-dbhome"
  }

  # License Model
  license_model = var.license_model

  # Display Name
  display_name = "${var.name_prefix}-db-system"

  # Tags
  freeform_tags = merge(
    var.tags,
    {
      Name    = "${var.name_prefix}-db-system"
      Cluster = var.cluster_name
    }
  )

  # Lifecycle - prevent accidental deletion
  lifecycle {
    ignore_changes = [
      db_home[0].database[0].admin_password # Don't update password on every apply
    ]
  }
}
