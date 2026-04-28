# Confluent Cloud Provider Configuration
provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

# Confluent Cloud Environment
# Use existing environment (always uses existing - specify via variable)
data "confluent_environment" "main" {
  id = var.confluent_environment_id
}

# Data source for existing Confluent Cloud network
data "confluent_network" "existing" {
  count = var.create_confluent_network ? 0 : 1
  id    = var.existing_confluent_network_id
  environment {
    id = data.confluent_environment.main.id
  }
}

# Azure Egress Network - Create new or use existing
# This is the CCN (Confluent Cloud Network) for private connectivity
resource "confluent_network" "egress" {
  count            = var.create_confluent_network ? 1 : 0
  display_name     = "${var.resource_prefix}-egress-network"
  cloud            = "AZURE"
  region           = var.confluent_cloud_region
  connection_types = ["PRIVATELINK"]
  environment {
    id = data.confluent_environment.main.id
  }

  # DNS configuration for private connectivity
  dns_config {
    resolution = "PRIVATE"
  }
}

# Local values to reference the correct network
locals {
  confluent_network_id = var.create_confluent_network ? confluent_network.egress[0].id : data.confluent_network.existing[0].id
}

# Data source for existing Private Link Attachment
data "confluent_private_link_attachment" "existing" {
  count = var.create_private_link_attachment ? 0 : 1
  id    = var.existing_private_link_attachment_id
  environment {
    id = data.confluent_environment.main.id
  }
}

# Private Link Attachment - Create new or use existing
resource "confluent_private_link_attachment" "appgw" {
  count        = var.create_private_link_attachment ? 1 : 0
  display_name = "${var.resource_prefix}-appgw-attachment"
  cloud        = "AZURE"
  region       = var.confluent_cloud_region
  environment {
    id = data.confluent_environment.main.id
  }
}

# Local values to reference the correct private link attachment
locals {
  private_link_attachment_id = var.create_private_link_attachment ? confluent_private_link_attachment.appgw[0].id : data.confluent_private_link_attachment.existing[0].id
}

# Egress Access Point - Azure Private Link to Application Gateway
# Uses the gateway from the existing Confluent network
resource "confluent_access_point" "appgw_egress" {
  display_name = "${var.resource_prefix}-appgw-egress"

  environment {
    id = data.confluent_environment.main.id
  }

  gateway {
    # Use the gateway ID from the existing network
    id = data.confluent_network.existing[0].gateway[0].id
  }

  azure_egress_private_link_endpoint {
    private_link_service_resource_id = azurerm_application_gateway.main.id
    # For Application Gateway, the subresource must be the private frontend IP configuration
    private_link_subresource_name = "appgw-frontend-private"
  }

  depends_on = [
    azurerm_application_gateway.main,
    confluent_private_link_attachment.appgw
  ]
}

# DNS Record for Egress Access Point (optional)
resource "confluent_dns_record" "appgw_egress" {
  count        = var.create_dns_record ? 1 : 0
  display_name = "${var.resource_prefix}-appgw-dns"
  domain       = var.dns_domain

  environment {
    id = data.confluent_environment.main.id
  }

  gateway {
    id = data.confluent_network.existing[0].gateway[0].id
  }

  private_link_access_point {
    id = confluent_access_point.appgw_egress.id
  }

  depends_on = [
    confluent_access_point.appgw_egress
  ]
}

# IBM MQ Source Connector
resource "confluent_connector" "ibm_mq_source" {
  count = var.create_connector ? 1 : 0

  environment {
    id = data.confluent_environment.main.id
  }

  kafka_cluster {
    id = var.kafka_cluster_id
  }

  config_sensitive = {
    "kafka.api.key"    = var.kafka_api_key
    "kafka.api.secret" = var.kafka_api_secret
    "mq.password"      = var.mq_password != "" ? var.mq_password : null
  }

  config_nonsensitive = merge({
    "connector.class" = "IbmMQSource"
    "name"            = var.connector_name
    "kafka.auth.mode" = "KAFKA_API_KEY"
    "kafka.topic"     = var.kafka_topic
    "tasks.max"       = tostring(var.connector_tasks_max)

    # MQ Connection Settings - use DNS name if created, otherwise use access point IP
    "mq.hostname"      = var.create_dns_record ? var.dns_domain : confluent_access_point.appgw_egress.azure_egress_private_link_endpoint[0].private_endpoint_ip_address
    "mq.port"          = tostring(var.ibm_mq_frontend_port)
    "mq.transport"     = var.mq_transport
    "mq.queue.manager" = var.mq_queue_manager
    "mq.channel"       = var.mq_channel

    # JMS Settings
    "jms.destination.name" = var.jms_destination_name
    "jms.destination.type" = var.jms_destination_type

    # Output format
    "key.converter"                  = "org.apache.kafka.connect.storage.StringConverter"
    "value.converter"                = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter.schemas.enable" = "false"
    "output.data.format"             = "JSON"
    },
    var.mq_username != "" ? { "mq.username" = var.mq_username } : {},
    var.mq_ssl_cipher_suite != "" ? {
      "mq.ssl.cipher.suite"        = var.mq_ssl_cipher_suite
      "mq.ssl.keystore.location"   = var.mq_ssl_keystore_location
      "mq.ssl.keystore.password"   = var.mq_ssl_keystore_password
      "mq.ssl.truststore.location" = var.mq_ssl_truststore_location
      "mq.ssl.truststore.password" = var.mq_ssl_truststore_password
  } : {})

  depends_on = [
    confluent_access_point.appgw_egress
  ]
}

# Oracle XStream CDC Connector
resource "confluent_connector" "oracle_xstream" {
  count = var.create_oracle_connector ? 1 : 0

  environment {
    id = data.confluent_environment.main.id
  }

  kafka_cluster {
    id = var.kafka_cluster_id
  }

  config_sensitive = {
    "kafka.api.key"    = var.kafka_api_key
    "kafka.api.secret" = var.kafka_api_secret
    "oracle.password"  = var.oracle_db_password
  }

  config_nonsensitive = {
    "connector.class" = "OracleXstreamCdc"
    "name"            = var.oracle_connector_name
    "kafka.auth.mode" = "KAFKA_API_KEY"
    "tasks.max"       = tostring(var.connector_tasks_max)

    # Oracle Connection Settings
    # Use Oracle VM private IP if provisioned, otherwise use configured hostname
    "oracle.server"   = var.provision_oracle_database ? module.oracle_database[0].oracle_private_ip : var.oracle_db_hostname
    "oracle.port"     = tostring(var.oracle_backend_port)
    "oracle.username" = var.oracle_db_user

    # Database Configuration
    "oracle.database"         = var.oracle_db_name
    "oracle.pdb.name"         = var.oracle_pdb_name
    "oracle.out.server.name"  = var.oracle_out_server_name

    # Table Selection
    "table.include.list" = var.oracle_table_include_list

    # Topic Configuration
    "topic.prefix"    = var.oracle_topic_prefix
    "snapshot.mode"   = var.oracle_snapshot_mode

    # Output Format
    "key.converter"                  = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter"                = "org.apache.kafka.connect.json.JsonConverter"
    "key.converter.schemas.enable"   = "false"
    "value.converter.schemas.enable" = "false"
    "output.data.format"             = "JSON"

    # Performance tuning
    "snapshot.fetch.size" = var.oracle_snapshot_fetch_size
  }

  depends_on = [
    confluent_access_point.appgw_egress,
    module.oracle_database
  ]
}
