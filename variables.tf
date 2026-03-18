variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "westeurope"
}

variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "confluent-pl"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "appgw_subnet_prefix" {
  description = "Address prefix for Application Gateway subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "backend_subnet_prefix" {
  description = "Address prefix for backend resources subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Purpose     = "confluent-privatelink"
    ManagedBy   = "terraform"
  }
}

variable "appgw_sku" {
  description = "SKU for Application Gateway"
  type = object({
    name     = string
    tier     = string
    capacity = number
  })
  default = {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }
}

variable "ibm_mq_backend_targets" {
  description = "List of IBM MQ backend targets (IP addresses or FQDNs)"
  type        = list(string)
  default     = []
}

variable "ibm_mq_backend_port" {
  description = "Port for IBM MQ server"
  type        = number
  default     = 1414
}

variable "ibm_mq_frontend_port" {
  description = "Frontend port for IBM MQ listener"
  type        = number
  default     = 1414
}
