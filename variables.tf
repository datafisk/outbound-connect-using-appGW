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

# Resource Group Configuration
variable "create_resource_group" {
  description = "Whether to create a new resource group or use an existing one"
  type        = bool
  default     = true
}

variable "existing_resource_group_name" {
  description = "Name of existing resource group to use (if create_resource_group is false)"
  type        = string
  default     = ""
}

# VNet Configuration
variable "create_vnet" {
  description = "Whether to create a new VNet or use an existing one"
  type        = bool
  default     = true
}

variable "existing_vnet_name" {
  description = "Name of existing VNet to use (if create_vnet is false)"
  type        = string
  default     = ""
}

variable "existing_vnet_resource_group_name" {
  description = "Resource group of existing VNet (if different from main resource group)"
  type        = string
  default     = ""
}

variable "vnet_address_space" {
  description = "Address space for the virtual network (only used if create_vnet is true)"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

# Subnet Configuration
variable "create_subnets" {
  description = "Whether to create new subnets or use existing ones"
  type        = bool
  default     = true
}

variable "existing_appgw_subnet_name" {
  description = "Name of existing Application Gateway subnet (if create_subnets is false)"
  type        = string
  default     = ""
}

variable "appgw_subnet_prefix" {
  description = "Address prefix for Application Gateway subnet (only used if create_subnets is true)"
  type        = string
  default     = "10.0.1.0/24"
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

# Confluent Cloud Configuration
variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key"
  type        = string
  sensitive   = true
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
  sensitive   = true
}

variable "confluent_environment_id" {
  description = "Confluent Cloud Environment ID"
  type        = string
}

variable "confluent_cloud_region" {
  description = "Confluent Cloud region (must match Azure region)"
  type        = string
  default     = "westeurope"
}

variable "azure_subscription_id" {
  description = "Azure Subscription ID for Private Link"
  type        = string
}

# Confluent Network Configuration
variable "create_confluent_network" {
  description = "Whether to create a new Confluent Cloud network or use an existing one"
  type        = bool
  default     = true
}

variable "existing_confluent_network_id" {
  description = "ID of existing Confluent Cloud network (if create_confluent_network is false)"
  type        = string
  default     = ""
}

# Confluent Private Link Configuration
variable "create_private_link_attachment" {
  description = "Whether to create a new Private Link Attachment or use an existing one"
  type        = bool
  default     = true
}

variable "existing_private_link_attachment_id" {
  description = "ID of existing Private Link Attachment (if create_private_link_attachment is false)"
  type        = string
  default     = ""
}

# DNS Configuration
variable "create_dns_record" {
  description = "Whether to create a DNS record for the egress access point"
  type        = bool
  default     = false
}

variable "dns_domain" {
  description = "Custom DNS domain name for the egress access point (e.g., 'mq.example.com')"
  type        = string
  default     = ""
}

# Connector Configuration
variable "create_connector" {
  description = "Whether to create the IBM MQ Source connector"
  type        = bool
  default     = false
}

variable "connector_name" {
  description = "Name for the IBM MQ Source connector"
  type        = string
  default     = "ibm-mq-source-connector"
}

variable "kafka_cluster_id" {
  description = "Kafka cluster ID where the connector will be deployed"
  type        = string
  default     = ""
}

variable "kafka_api_key" {
  description = "Kafka cluster API key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "kafka_api_secret" {
  description = "Kafka cluster API secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "kafka_topic" {
  description = "Kafka topic to write IBM MQ messages to"
  type        = string
  default     = "ibm-mq-messages"
}

variable "connector_tasks_max" {
  description = "Maximum number of tasks for the connector"
  type        = number
  default     = 1
}

# IBM MQ Configuration
variable "mq_transport" {
  description = "IBM MQ transport type (typically 'client')"
  type        = string
  default     = "client"
}

variable "mq_queue_manager" {
  description = "IBM MQ Queue Manager name"
  type        = string
  default     = "QM1"
}

variable "mq_channel" {
  description = "IBM MQ Server Connection Channel name"
  type        = string
  default     = "DEV.APP.SVRCONN"
}

variable "mq_username" {
  description = "IBM MQ username (optional)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "mq_password" {
  description = "IBM MQ password (optional)"
  type        = string
  sensitive   = true
  default     = ""
}

# JMS Configuration
variable "jms_destination_name" {
  description = "JMS destination (queue or topic) name"
  type        = string
  default     = "DEV.QUEUE.1"
}

variable "jms_destination_type" {
  description = "JMS destination type (queue or topic)"
  type        = string
  default     = "queue"
}

# SSL/TLS Configuration (Optional)
variable "mq_ssl_cipher_suite" {
  description = "IBM MQ SSL cipher suite (optional)"
  type        = string
  default     = ""
}

variable "mq_ssl_keystore_location" {
  description = "Path to keystore file (optional)"
  type        = string
  default     = ""
}

variable "mq_ssl_keystore_password" {
  description = "Keystore password (optional)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "mq_ssl_truststore_location" {
  description = "Path to truststore file (optional)"
  type        = string
  default     = ""
}

variable "mq_ssl_truststore_password" {
  description = "Truststore password (optional)"
  type        = string
  sensitive   = true
  default     = ""
}
