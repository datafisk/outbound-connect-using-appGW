# Root Module Variables for Oracle RAC on OCI
# Values are set in terraform.tfvars

variable "compartment_id" {
  description = "OCID of the compartment"
  type        = string
}

variable "availability_domain" {
  description = "Availability domain name"
  type        = string
}

variable "use_existing_vcn" {
  description = "Use existing VCN"
  type        = bool
  default     = false
}

variable "existing_vcn_id" {
  description = "OCID of existing VCN"
  type        = string
  default     = ""
}

variable "use_existing_client_subnet" {
  description = "Use existing client subnet"
  type        = bool
  default     = false
}

variable "existing_client_subnet_id" {
  description = "OCID of existing client subnet"
  type        = string
  default     = ""
}

variable "backup_subnet_cidr" {
  description = "CIDR for backup subnet"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "cluster_name" {
  description = "RAC cluster name"
  type        = string
}

variable "hostname_prefix" {
  description = "Hostname prefix for RAC nodes"
  type        = string
}

variable "db_system_shape" {
  description = "DB System VM shape"
  type        = string
}

variable "cpu_core_count" {
  description = "Number of CPU cores"
  type        = number
}

variable "data_storage_size_gb" {
  description = "Data storage size in GB"
  type        = number
}

variable "db_edition" {
  description = "Oracle Database edition"
  type        = string
}

variable "db_admin_password" {
  description = "Database admin password"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "pdb_name" {
  description = "PDB name"
  type        = string
}

variable "db_version" {
  description = "Oracle Database version"
  type        = string
}

variable "db_workload" {
  description = "Database workload type"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key"
  type        = string
}

variable "license_model" {
  description = "License model"
  type        = string
}

variable "auto_backup_enabled" {
  description = "Enable automatic backups"
  type        = bool
}

variable "auto_backup_window" {
  description = "Backup window"
  type        = string
}

variable "recovery_window_in_days" {
  description = "Backup retention days"
  type        = number
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
}
