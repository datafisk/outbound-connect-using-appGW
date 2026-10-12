# Azure Application Gateway - Add Oracle RAC Routing Rule
# This adds a TCP routing rule to the existing peter-g-mqtt AppGW

provider "azurerm" {
  features {}
}

# Variables
variable "appgw_idle_timeout_minutes" {
  description = "Application Gateway idle timeout in minutes (1-20). Recommended: 10-15 minutes for long-lived connections like Oracle RAC. IMPORTANT: The timeout parameter in backend_settings expects seconds (1-86400), so this value will be converted."
  type        = number
  default     = 15
  validation {
    condition     = var.appgw_idle_timeout_minutes >= 1 && var.appgw_idle_timeout_minutes <= 20
    error_message = "Application Gateway idle timeout must be between 1 and 20 minutes."
  }
}

# Data source for existing AppGW
data "azurerm_application_gateway" "peter_g_mqtt" {
  name                = "peter-g-mqtt"
  resource_group_name = "vpc-peered-cce-se"
}

# Resource to manage the routing rule
resource "azurerm_application_gateway" "peter_g_mqtt_update" {
  name                = data.azurerm_application_gateway.peter_g_mqtt.name
  resource_group_name = data.azurerm_application_gateway.peter_g_mqtt.resource_group_name
  location            = data.azurerm_application_gateway.peter_g_mqtt.location

  # Copy existing SKU
  sku {
    name     = data.azurerm_application_gateway.peter_g_mqtt.sku[0].name
    tier     = data.azurerm_application_gateway.peter_g_mqtt.sku[0].tier
    capacity = length(lookup(data.azurerm_application_gateway.peter_g_mqtt, "autoscale_configuration", [])) == 0 ? data.azurerm_application_gateway.peter_g_mqtt.sku[0].capacity : null
  }

  # Copy autoscale configuration if it exists
  dynamic "autoscale_configuration" {
    for_each = lookup(data.azurerm_application_gateway.peter_g_mqtt, "autoscale_configuration", [])
    content {
      min_capacity = autoscale_configuration.value.min_capacity
      max_capacity = lookup(autoscale_configuration.value, "max_capacity", null)
    }
  }

  # Copy existing gateway IP configurations
  dynamic "gateway_ip_configuration" {
    for_each = data.azurerm_application_gateway.peter_g_mqtt.gateway_ip_configuration
    content {
      name      = gateway_ip_configuration.value.name
      subnet_id = gateway_ip_configuration.value.subnet_id
    }
  }

  # Copy existing frontend ports
  dynamic "frontend_port" {
    for_each = data.azurerm_application_gateway.peter_g_mqtt.frontend_port
    content {
      name = frontend_port.value.name
      port = frontend_port.value.port
    }
  }

  # Copy existing frontend IP configurations
  dynamic "frontend_ip_configuration" {
    for_each = data.azurerm_application_gateway.peter_g_mqtt.frontend_ip_configuration
    content {
      name                          = frontend_ip_configuration.value.name
      subnet_id                     = frontend_ip_configuration.value.subnet_id
      private_ip_address            = frontend_ip_configuration.value.private_ip_address
      private_ip_address_allocation = frontend_ip_configuration.value.private_ip_address_allocation
      public_ip_address_id          = frontend_ip_configuration.value.public_ip_address_id
    }
  }

  # Copy existing backend address pools
  dynamic "backend_address_pool" {
    for_each = data.azurerm_application_gateway.peter_g_mqtt.backend_address_pool
    content {
      name         = backend_address_pool.value.name
      ip_addresses = backend_address_pool.value.ip_addresses
      fqdns        = backend_address_pool.value.fqdns
    }
  }

  # Add new Oracle RAC backend pool (using VIP IPs for RAC failover)
  backend_address_pool {
    name         = "oracle_rac_oci"
    ip_addresses = ["10.99.1.165", "10.99.1.84"]  # racnode1-vip, racnode2-vip
  }

  # Copy existing backend HTTP settings
  dynamic "backend_http_settings" {
    for_each = [
      for s in data.azurerm_application_gateway.peter_g_mqtt.backend_http_settings : s
      if s.protocol == "Http" || s.protocol == "Https"
    ]
    content {
      name                  = backend_http_settings.value.name
      cookie_based_affinity = backend_http_settings.value.cookie_based_affinity
      port                  = backend_http_settings.value.port
      protocol              = backend_http_settings.value.protocol
      request_timeout       = backend_http_settings.value.request_timeout
    }
  }

  # Copy existing backend (TCP)
  dynamic "backend" {
    for_each = [
      for s in lookup(data.azurerm_application_gateway.peter_g_mqtt, "backend", []) : s
      if lookup(s, "protocol", "") == "Tcp" && s.name != "oracle_1521"
    ]
    content {
      name     = backend.value.name
      port     = backend.value.port
      protocol = backend.value.protocol
    }
  }

  # Ensure oracle_1521 backend exist
  backend {
    name               = "oracle_1521"
    port               = 1521
    protocol           = "Tcp"
    timeout_in_seconds = var.appgw_idle_timeout_minutes * 60 # Convert minutes to seconds (Azure requires 1-86400 seconds)
  }

  # Copy existing HTTP listeners
  dynamic "http_listener" {
    for_each = data.azurerm_application_gateway.peter_g_mqtt.http_listener
    content {
      name                           = http_listener.value.name
      frontend_ip_configuration_name = http_listener.value.frontend_ip_configuration_name
      frontend_port_name             = http_listener.value.frontend_port_name
      protocol                       = http_listener.value.protocol
    }
  }

  # Copy existing listeners (TCP)
  dynamic "listener" {
    for_each = lookup(data.azurerm_application_gateway.peter_g_mqtt, "listener", [])
    content {
      name                           = listener.value.name
      frontend_ip_configuration_name = listener.value.frontend_ip_configuration_name
      frontend_port_name             = listener.value.frontend_port_name
      protocol                       = listener.value.protocol
    }
  }

  # Ensure oracle_standalone TCP listener exists
  listener {
    name                           = "oracle_standalone"
    frontend_ip_configuration_name = "appGwPrivateFrontendIpIPv4"
    frontend_port_name             = "port_1521"
    protocol                       = "Tcp"
  }

  # Copy existing request routing rules
  dynamic "request_routing_rule" {
    for_each = [
      for r in data.azurerm_application_gateway.peter_g_mqtt.request_routing_rule : r
      if r.name != "route-to-oracle-standalone"
    ]
    content {
      name                       = request_routing_rule.value.name
      rule_type                  = request_routing_rule.value.rule_type
      http_listener_name         = request_routing_rule.value.http_listener_name
      backend_address_pool_name  = request_routing_rule.value.backend_address_pool_name
      backend_http_settings_name = request_routing_rule.value.backend_http_settings_name
      priority                   = request_routing_rule.value.priority
    }
  }

  # Copy existing routing rules (TCP)
  dynamic "routing_rule" {
    for_each = [
      for r in lookup(data.azurerm_application_gateway.peter_g_mqtt, "routing_rule", []) : r
      if r.name != "route-to-oracle-rac-oci"
    ]
    content {
      name                      = routing_rule.value.name
      priority                  = routing_rule.value.priority
      listener_name             = routing_rule.value.listener_name
      backend_address_pool_name = routing_rule.value.backend_address_pool_name
      backend_name              = routing_rule.value.backend_name
    }
  }

  # Add new Oracle RAC routing rule
  routing_rule {
    name                      = "route-to-oracle-rac-oci"
    priority                  = 110
    listener_name             = "oracle_standalone"
    backend_address_pool_name = "oracle_rac_oci"
    backend_name              = "oracle_1521"
  }

  # Copy existing probes (excluding oracle_rac_probe as we'll define it separately)
  dynamic "probe" {
    for_each = [
      for p in data.azurerm_application_gateway.peter_g_mqtt.probe : p
      if p.name != "oracle_rac_probe"
    ]
    content {
      name                = probe.value.name
      protocol            = probe.value.protocol
      path                = probe.value.protocol == "Tcp" ? null : lookup(probe.value, "path", "/")
      host                = probe.value.protocol == "Tcp" ? null : lookup(probe.value, "host", "127.0.0.1")
      interval            = probe.value.interval
      timeout             = probe.value.timeout
      unhealthy_threshold = probe.value.unhealthy_threshold
      port                = lookup(probe.value, "port", null)
    }
  }

  # Add Oracle RAC health probe
  probe {
    name                = "oracle_rac_probe"
    protocol            = "Tcp"
    port                = 1521
    interval            = 30
    timeout             = 10
    unhealthy_threshold = 3
  }
}

# Output the AppGW private IP
output "appgw_private_ip" {
  value       = "172.200.9.19"
  description = "AppGW Private Frontend IP for EAP configuration"
}

output "oracle_rac_connection" {
  value       = "Use EAP hostname:1521 for JDBC connection"
  description = "Connection string format for Confluent Oracle connector"
}
