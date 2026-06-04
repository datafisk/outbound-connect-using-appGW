# ============================================================================
# Oracle JDBC Source Connector Variables
# ============================================================================

# ---------------------------
# Connector Control
# ---------------------------

variable "create_oracle_connector" {
  description = "Whether to create the Oracle JDBC Source Connector"
  type        = bool
  default     = false
}

# ---------------------------
# Confluent Cloud Configuration
# ---------------------------

variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key for connector deployment"
  type        = string
  sensitive   = true
  default     = ""
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret for connector deployment"
  type        = string
  sensitive   = true
  default     = ""
}

variable "confluent_environment_id" {
  description = "Confluent Cloud Environment ID (e.g., env-xxxxx)"
  type        = string
  default     = ""
}

variable "kafka_cluster_id" {
  description = "Kafka Cluster ID where connector will be deployed (e.g., lkc-xxxxx)"
  type        = string
  default     = ""
}

variable "kafka_api_key" {
  description = "Kafka API Key for the connector to use"
  type        = string
  sensitive   = true
  default     = ""
}

variable "kafka_api_secret" {
  description = "Kafka API Secret for the connector to use"
  type        = string
  sensitive   = true
  default     = ""
}

# ---------------------------
# Connector Configuration
# ---------------------------

variable "oracle_connector_name" {
  description = "Name of the Oracle JDBC Source Connector"
  type        = string
  default     = "oracle-rac-jdbc-source"
}

variable "oracle_tasks_max" {
  description = "Maximum number of tasks for the connector"
  type        = number
  default     = 1
}

# ---------------------------
# Oracle Connection
# ---------------------------

variable "oracle_connection_host" {
  description = "Oracle RAC connection hostname (use SCAN name or AppGW IP with Confluent DNS wildcard)"
  type        = string
  default     = ""

  validation {
    condition     = var.oracle_connection_host == "" || can(regex("^[a-zA-Z0-9.-]+$", var.oracle_connection_host)) || can(cidrhost("${var.oracle_connection_host}/32", 0))
    error_message = "Oracle connection host must be a valid hostname or IP address."
  }
}

variable "oracle_connection_port" {
  description = "Oracle database port"
  type        = number
  default     = 1521
}

variable "oracle_username" {
  description = "Oracle database username for the connector"
  type        = string
  default     = "jdbc_connector"
}

variable "oracle_password" {
  description = "Oracle database password for the connector"
  type        = string
  sensitive   = true
  default     = ""
}

variable "oracle_db_name" {
  description = "Oracle database service name (fully qualified: pdb_name.domain)"
  type        = string
  default     = ""
}

variable "oracle_ssl_server_dn_match" {
  description = "Whether to match SSL server DN (set to false for self-signed certificates)"
  type        = bool
  default     = false
}

# ---------------------------
# Table Selection and CDC
# ---------------------------

variable "oracle_table_include_list" {
  description = "Comma-separated list of tables to include (format: SCHEMA.TABLE)"
  type        = string
  default     = ""
}

variable "oracle_mode" {
  description = "CDC mode: timestamp, incrementing, timestamp+incrementing, or bulk"
  type        = string
  default     = "timestamp+incrementing"

  validation {
    condition     = contains(["timestamp", "incrementing", "timestamp+incrementing", "bulk", ""], var.oracle_mode)
    error_message = "Oracle mode must be one of: timestamp, incrementing, timestamp+incrementing, bulk."
  }
}

variable "oracle_incrementing_column_mapping" {
  description = "Incrementing column mapping (format: SCHEMA.TABLE:[COLUMN])"
  type        = string
  default     = ""
}

variable "oracle_timestamp_columns_mapping" {
  description = "Timestamp column mapping (format: SCHEMA.TABLE:[COLUMN])"
  type        = string
  default     = ""
}

# ---------------------------
# Polling Configuration
# ---------------------------

variable "oracle_poll_interval_ms" {
  description = "Polling interval in milliseconds"
  type        = number
  default     = 5000
}

variable "oracle_batch_max_rows" {
  description = "Maximum number of rows to fetch in a single batch"
  type        = number
  default     = 100
}

# ---------------------------
# Output Configuration
# ---------------------------

variable "oracle_topic_prefix" {
  description = "Prefix for Kafka topics created by the connector"
  type        = string
  default     = "oracle-rac-"
}

variable "oracle_output_data_format" {
  description = "Output data format (JSON, AVRO, PROTOBUF)"
  type        = string
  default     = "JSON"

  validation {
    condition     = contains(["JSON", "AVRO", "PROTOBUF", ""], var.oracle_output_data_format)
    error_message = "Output data format must be one of: JSON, AVRO, PROTOBUF."
  }
}

variable "oracle_output_key_format" {
  description = "Output key format (JSON, AVRO, PROTOBUF)"
  type        = string
  default     = "JSON"

  validation {
    condition     = contains(["JSON", "AVRO", "PROTOBUF", ""], var.oracle_output_key_format)
    error_message = "Output key format must be one of: JSON, AVRO, PROTOBUF."
  }
}
