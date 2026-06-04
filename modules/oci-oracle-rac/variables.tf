# OCI Authentication (optional - uses ~/.oci/config by default)
variable "tenancy_ocid" {
  description = "OCID of the tenancy"
  type        = string
  default     = ""
}

variable "user_ocid" {
  description = "OCID of the user"
  type        = string
  default     = ""
}

variable "fingerprint" {
  description = "Fingerprint of the API key"
  type        = string
  default     = ""
}

variable "private_key_path" {
  description = "Path to private key file"
  type        = string
  default     = "~/.oci/oci_api_key.pem"
}

variable "region" {
  description = "OCI region"
  type        = string
  default     = "us-ashburn-1"
}

# Resource Configuration
variable "compartment_id" {
  description = "OCID of the compartment where resources will be created"
  type        = string
}

variable "availability_domain" {
  description = "Availability domain for the DB system (e.g., 'AD-1', 'AD-2', 'AD-3')"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "oracle-rac"
}

# Network Configuration
variable "use_existing_vcn" {
  description = "Use existing VCN instead of creating new one"
  type        = bool
  default     = false
}

variable "existing_vcn_id" {
  description = "OCID of existing VCN (required if use_existing_vcn = true)"
  type        = string
  default     = ""
}

variable "use_existing_client_subnet" {
  description = "Use existing subnet for client connections"
  type        = bool
  default     = false
}

variable "existing_client_subnet_id" {
  description = "OCID of existing client subnet (required if use_existing_client_subnet = true)"
  type        = string
  default     = ""
}

variable "vcn_cidr" {
  description = "CIDR block for the VCN (only used when creating new VCN)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vcn_dns_label" {
  description = "DNS label for the VCN (only used when creating new VCN)"
  type        = string
  default     = "racvcn"
}

variable "client_subnet_cidr" {
  description = "CIDR block for client subnet (only used when creating new subnet)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "backup_subnet_cidr" {
  description = "CIDR block for backup subnet"
  type        = string
  default     = "10.0.2.0/24"
}

# RAC Cluster Configuration
variable "cluster_name" {
  description = "Name of the RAC cluster"
  type        = string
  default     = "raccluster"
}

variable "hostname_prefix" {
  description = "Hostname prefix for DB nodes"
  type        = string
  default     = "racnode"
}

variable "node_count" {
  description = "Number of nodes in RAC cluster (2 for Base DB Service)"
  type        = number
  default     = 2

  validation {
    condition     = var.node_count == 2
    error_message = "OCI Base Database Service supports 2-node RAC only. Use Exadata for more nodes."
  }
}

# Database System Configuration
variable "db_system_shape" {
  description = "Shape for DB system VMs (e.g., 'VM.Standard2.4', 'VM.Standard2.8')"
  type        = string
  default     = "VM.Standard2.4"
}

variable "db_edition" {
  description = "Oracle Database edition"
  type        = string
  default     = "ENTERPRISE_EDITION_EXTREME_PERFORMANCE"

  validation {
    condition = contains([
      "STANDARD_EDITION",
      "ENTERPRISE_EDITION",
      "ENTERPRISE_EDITION_HIGH_PERFORMANCE",
      "ENTERPRISE_EDITION_EXTREME_PERFORMANCE"
    ], var.db_edition)
    error_message = "Invalid database edition. Must be STANDARD_EDITION, ENTERPRISE_EDITION, ENTERPRISE_EDITION_HIGH_PERFORMANCE, or ENTERPRISE_EDITION_EXTREME_PERFORMANCE."
  }
}

variable "cpu_core_count" {
  description = "Number of CPU cores to enable (must be compatible with shape)"
  type        = number
  default     = 4
}

variable "data_storage_size_gb" {
  description = "Data storage size in GB (minimum 256 GB for RAC)"
  type        = number
  default     = 512

  validation {
    condition     = var.data_storage_size_gb >= 256
    error_message = "Data storage must be at least 256 GB for RAC."
  }
}

variable "storage_management" {
  description = "Storage management software (ASM or LVM)"
  type        = string
  default     = "ASM"

  validation {
    condition     = contains(["ASM", "LVM"], var.storage_management)
    error_message = "Storage management must be ASM or LVM. ASM is required for RAC."
  }
}

# Database Configuration
variable "db_admin_password" {
  description = "Password for SYS and SYSTEM users (must be 9-30 chars, include uppercase, lowercase, and numbers)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_admin_password) >= 9 && length(var.db_admin_password) <= 30
    error_message = "Database admin password must be between 9 and 30 characters."
  }
}

variable "db_name" {
  description = "Database name (max 8 characters, alphanumeric only)"
  type        = string
  default     = "RACDB"

  validation {
    condition     = length(var.db_name) <= 8 && can(regex("^[a-zA-Z][a-zA-Z0-9]*$", var.db_name))
    error_message = "Database name must be max 8 alphanumeric characters, starting with a letter."
  }
}

variable "pdb_name" {
  description = "Pluggable database name (optional, for 12c+)"
  type        = string
  default     = "PDB1"

  validation {
    condition     = var.pdb_name == "" || (length(var.pdb_name) <= 30 && can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.pdb_name)))
    error_message = "PDB name must be max 30 alphanumeric characters plus underscore, starting with a letter."
  }
}

variable "db_version" {
  description = "Oracle Database version (e.g., '19.21.0.0', '21.10.0.0')"
  type        = string
  default     = "19.21.0.0"
}

variable "db_workload" {
  description = "Database workload type"
  type        = string
  default     = "OLTP"

  validation {
    condition     = contains(["OLTP", "DSS"], var.db_workload)
    error_message = "Database workload must be OLTP or DSS."
  }
}

variable "character_set" {
  description = "Database character set"
  type        = string
  default     = "AL32UTF8"
}

variable "ncharacter_set" {
  description = "Database national character set"
  type        = string
  default     = "AL16UTF16"
}

# SSH Access
variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

# License Configuration
variable "license_model" {
  description = "License model: LICENSE_INCLUDED or BRING_YOUR_OWN_LICENSE"
  type        = string
  default     = "BRING_YOUR_OWN_LICENSE"

  validation {
    condition     = contains(["LICENSE_INCLUDED", "BRING_YOUR_OWN_LICENSE"], var.license_model)
    error_message = "License model must be LICENSE_INCLUDED or BRING_YOUR_OWN_LICENSE."
  }
}

# Backup Configuration
variable "auto_backup_enabled" {
  description = "Enable automatic backups"
  type        = bool
  default     = true
}

variable "auto_backup_window" {
  description = "Backup window (e.g., 'SLOT_ONE' for 00:00-06:00 UTC)"
  type        = string
  default     = null
}

variable "recovery_window_in_days" {
  description = "Number of days to retain automatic backups"
  type        = number
  default     = 7
}

# Tags
variable "tags" {
  description = "Freeform tags for resources"
  type        = map(string)
  default     = {}
}
