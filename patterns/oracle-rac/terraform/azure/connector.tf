# Oracle JDBC Source Connector for RAC
# Deploys Confluent Cloud Oracle Database Source Connector to ingest data from Oracle RAC

# Confluent Cloud API credentials for connector deployment
provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

# Oracle JDBC Source Connector
resource "confluent_connector" "oracle_rac_source" {
  count = var.create_oracle_connector ? 1 : 0

  environment {
    id = var.confluent_environment_id
  }

  kafka_cluster {
    id = var.kafka_cluster_id
  }

  config_sensitive = {
    "kafka.api.key"       = var.kafka_api_key
    "kafka.api.secret"    = var.kafka_api_secret
    "connection.password" = var.oracle_password
  }

  config_nonsensitive = {
    "name"            = var.oracle_connector_name
    "connector.class" = "OracleDatabaseSource"
    "kafka.auth.mode" = "KAFKA_API_KEY"
    "tasks.max"       = tostring(var.oracle_tasks_max)

    # Oracle Connection
    "connection.host" = var.oracle_connection_host
    "connection.port" = tostring(var.oracle_connection_port)
    "connection.user" = var.oracle_username
    "db.name"         = var.oracle_db_name

    # SSL/TLS (optional)
    "oracle.net.ssl_server_dn_match" = tostring(var.oracle_ssl_server_dn_match)

    # Table Selection
    "table.include.list" = var.oracle_table_include_list

    # CDC Mode
    "mode"                        = var.oracle_mode
    "incrementing.column.mapping" = var.oracle_incrementing_column_mapping
    "timestamp.columns.mapping"   = var.oracle_timestamp_columns_mapping

    # Polling Configuration
    "poll.interval.ms" = tostring(var.oracle_poll_interval_ms)
    "batch.max.rows"   = tostring(var.oracle_batch_max_rows)

    # Output Configuration
    "topic.prefix"       = var.oracle_topic_prefix
    "output.data.format" = var.oracle_output_data_format
    "output.key.format"  = var.oracle_output_key_format
  }

  depends_on = [
    azurerm_application_gateway.peter_g_mqtt_update
  ]

  lifecycle {
    prevent_destroy = false
  }
}
