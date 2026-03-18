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
