# Confluent Cloud Provider Configuration
terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 1.0"
    }
  }
}

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

  azure {
    subscription_id = var.azure_subscription_id
  }
}

# Local values to reference the correct private link attachment
locals {
  private_link_attachment_id = var.create_private_link_attachment ? confluent_private_link_attachment.appgw[0].id : data.confluent_private_link_attachment.existing[0].id
}

# Egress Endpoint to Application Gateway Private Link
resource "confluent_private_link_attachment_connection" "appgw" {
  display_name = "${var.resource_prefix}-appgw-connection"

  environment {
    id = data.confluent_environment.main.id
  }

  private_link_attachment {
    id = local.private_link_attachment_id
  }

  azure {
    private_link_service_resource_id = azurerm_application_gateway.main.id
  }

  depends_on = [
    azurerm_application_gateway.main
  ]
}
