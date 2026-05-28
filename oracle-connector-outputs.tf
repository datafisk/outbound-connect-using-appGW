# ============================================================================
# Oracle JDBC Source Connector Outputs
# ============================================================================

output "oracle_connector_id" {
  description = "ID of the Oracle JDBC Source Connector"
  value       = var.create_oracle_connector ? confluent_connector.oracle_rac_source[0].id : null
}

output "oracle_connector_name" {
  description = "Name of the Oracle JDBC Source Connector"
  value       = var.create_oracle_connector ? confluent_connector.oracle_rac_source[0].config_nonsensitive["name"] : null
}

output "oracle_connector_status" {
  description = "Status of the Oracle JDBC Source Connector"
  value       = var.create_oracle_connector ? confluent_connector.oracle_rac_source[0].status : null
}

output "oracle_connector_topic_prefix" {
  description = "Topic prefix used by the Oracle connector"
  value       = var.create_oracle_connector ? var.oracle_topic_prefix : null
}

output "oracle_connector_expected_topics" {
  description = "Expected Kafka topics created by the connector (based on table include list)"
  value = var.create_oracle_connector && var.oracle_table_include_list != "" ? [
    for table in split(",", replace(var.oracle_table_include_list, " ", "")) :
    "${var.oracle_topic_prefix}${replace(table, ".", "_")}"
  ] : []
}

output "oracle_connector_connection_details" {
  description = "Oracle connection details (non-sensitive)"
  value = var.create_oracle_connector ? {
    host     = var.oracle_connection_host
    port     = var.oracle_connection_port
    db_name  = var.oracle_db_name
    username = var.oracle_username
    mode     = var.oracle_mode
  } : null
}

output "oracle_connector_verification_commands" {
  description = "Commands to verify the Oracle connector deployment"
  value = var.create_oracle_connector ? (<<-EOT
Verify Oracle JDBC Source Connector:

# Check connector status
confluent connect cluster describe ${confluent_connector.oracle_rac_source[0].id}

# List topics created by connector
confluent kafka topic list | grep '${var.oracle_topic_prefix}'

# Consume from a topic (example)
confluent kafka topic consume ${var.oracle_topic_prefix}${split(",", replace(var.oracle_table_include_list, " ", ""))[0]} --from-beginning
EOT
  ) : "Oracle connector not created (create_oracle_connector = false)"
}
