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

# Oracle Backend Configuration
variable "oracle_backend_targets" {
  description = "List of Oracle backend targets (IP addresses or FQDNs)"
  type        = list(string)
  default     = []
}

variable "oracle_backend_port" {
  description = "Port for Oracle server"
  type        = number
  default     = 1521
}

variable "oracle_frontend_port" {
  description = "Frontend port for Oracle listener"
  type        = number
  default     = 1521
}

# Oracle Database Provisioning (Optional)
variable "provision_oracle_database" {
  description = "Whether to provision Oracle Database VM"
  type        = bool
  default     = false
}

variable "oracle_vm_size" {
  description = "Azure VM size for Oracle Database"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "oracle_ssh_public_key" {
  description = "SSH public key for Oracle VM"
  type        = string
  default     = ""
}

variable "oracle_ssh_private_key_path" {
  description = "Path to SSH private key for Oracle VM provisioning"
  type        = string
  default     = "~/.ssh/id_rsa"
}

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

# Oracle DNS Configuration
variable "oracle_dns_domain" {
  description = "Custom DNS domain name for Oracle egress access point"
  type        = string
  default     = ""
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

# Oracle XStream Connector Configuration
variable "create_oracle_connector" {
  description = "Whether to create the Oracle XStream CDC connector"
  type        = bool
  default     = false
}

variable "oracle_connector_name" {
  description = "Name for the Oracle XStream connector"
  type        = string
  default     = "oracle-xstream-cdc-connector"
}

variable "oracle_db_user" {
  description = "Oracle XStream user (typically C##GGADMIN)"
  type        = string
  sensitive   = true
  default     = "C##GGADMIN"
}

variable "oracle_db_password" {
  description = "Oracle XStream user password"
  type        = string
  sensitive   = true
  default     = "Confluent12!"
}

variable "oracle_db_hostname" {
  description = "Oracle database hostname (uses DNS record if created, otherwise Private Link IP)"
  type        = string
  default     = ""
}

variable "oracle_db_port" {
  description = "Oracle database port"
  type        = number
  default     = 1521
}

variable "oracle_db_name" {
  description = "Oracle database CDB name"
  type        = string
  default     = "XE"
}

variable "oracle_service_name" {
  description = "Oracle database service name"
  type        = string
  default     = "XE"
}

variable "oracle_out_server_name" {
  description = "XStream outbound server name"
  type        = string
  default     = "XOUT"
}

variable "oracle_table_include_list" {
  description = "Tables to capture from Oracle (regex pattern)"
  type        = string
  default     = "ORDERMGMT[.](ORDER_ITEMS|ORDERS|EMPLOYEES|PRODUCTS|CUSTOMERS|INVENTORIES|PRODUCT_CATEGORIES)"
}

variable "oracle_topic_prefix" {
  description = "Kafka topic prefix for Oracle data"
  type        = string
  default     = "oracle"
}

variable "oracle_snapshot_mode" {
  description = "Snapshot mode for initial load (initial, initial_only, schema_only, never)"
  type        = string
  default     = "initial"
}

variable "oracle_snapshot_fetch_size" {
  description = "Number of rows to fetch per database query during snapshot"
  type        = string
  default     = "10000"
}

variable "oracle_kafka_topic" {
  description = "Kafka topic for Oracle CDC data (optional, overrides topic_prefix)"
  type        = string
  default     = ""
}
