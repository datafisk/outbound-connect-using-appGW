variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string
}

variable "vnet_resource_group_name" {
  description = "Resource group name where VNet is located (defaults to resource_group_name)"
  type        = string
  default     = ""
}

variable "create_subnet" {
  description = "Whether to create a new subnet for Oracle"
  type        = bool
  default     = true
}

variable "existing_subnet_id" {
  description = "ID of existing subnet to use (if create_subnet is false)"
  type        = string
  default     = ""
}

variable "oracle_subnet_prefix" {
  description = "Address prefix for Oracle subnet"
  type        = string
  default     = "10.0.5.0/24"
}

variable "appgw_subnet_prefix" {
  description = "Application Gateway subnet CIDR (for NSG rules)"
  type        = string
  default     = ""
}

variable "create_nsg" {
  description = "Whether to create and manage NSG (set to false when using existing subnet with existing NSG)"
  type        = bool
  default     = true
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH access"
  type        = string
  default     = "0.0.0.0/0"
}

variable "create_public_ip" {
  description = "Whether to create a public IP for SSH access"
  type        = bool
  default     = true
}

variable "oracle_private_ip" {
  description = "Static private IP for Oracle VM (optional)"
  type        = string
  default     = ""
}

variable "vm_size" {
  description = "Azure VM size for Oracle"
  type        = string
  default     = "Standard_D4s_v3" # 4 vCPUs, 16 GB RAM
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB"
  type        = number
  default     = 256
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "oracleadmin"
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for provisioning"
  type        = string
}

# Oracle Database Configuration
variable "oracle_sys_password" {
  description = "Oracle SYS password"
  type        = string
  sensitive   = true
  default     = "Confluent123!"
}

variable "oracle_pdb_name" {
  description = "Oracle PDB name"
  type        = string
  default     = "XEPDB1"
}

variable "oracle_characterset" {
  description = "Oracle character set"
  type        = string
  default     = "AL32UTF8"
}

variable "oracle_memory_mb" {
  description = "Oracle SGA memory in MB"
  type        = number
  default     = 4000
}

variable "enable_archivelog" {
  description = "Enable archive log mode (required for CDC)"
  type        = bool
  default     = true
}

variable "configure_xstream" {
  description = "Whether to automatically configure XStream CDC"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
