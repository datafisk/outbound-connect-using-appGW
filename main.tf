# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.resource_prefix}-rg"
  location = var.location
  tags     = var.tags
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${var.resource_prefix}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# Subnet for Application Gateway
resource "azurerm_subnet" "appgw" {
  name                                          = "${var.resource_prefix}-appgw-subnet"
  resource_group_name                           = azurerm_resource_group.main.name
  virtual_network_name                          = azurerm_virtual_network.main.name
  address_prefixes                              = [var.appgw_subnet_prefix]
  private_link_service_network_policies_enabled = false
}

# Subnet for backend resources (IBM MQ, etc.)
resource "azurerm_subnet" "backend" {
  name                 = "${var.resource_prefix}-backend-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.backend_subnet_prefix]
}

# Network Security Group for Application Gateway subnet
resource "azurerm_network_security_group" "appgw" {
  name                = "${var.resource_prefix}-appgw-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  # Allow inbound traffic from GatewayManager
  security_rule {
    name                       = "AllowGatewayManager"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  # Allow inbound IBM MQ
  security_rule {
    name                       = "AllowIBMMQ"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1414"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow Azure Load Balancer
  security_rule {
    name                       = "AllowAzureLoadBalancer"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
}

# Associate NSG with Application Gateway subnet
resource "azurerm_subnet_network_security_group_association" "appgw" {
  subnet_id                 = azurerm_subnet.appgw.id
  network_security_group_id = azurerm_network_security_group.appgw.id
}

# Public IP for Application Gateway
resource "azurerm_public_ip" "appgw" {
  name                = "${var.resource_prefix}-appgw-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Application Gateway with TCP support for IBM MQ
resource "azurerm_application_gateway" "main" {
  name                = "${var.resource_prefix}-appgw"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  sku {
    name     = var.appgw_sku.name
    tier     = var.appgw_sku.tier
    capacity = var.appgw_sku.capacity
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.appgw.id
  }

  # Frontend configuration for public access
  frontend_ip_configuration {
    name                 = "appgw-frontend-public"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  # Frontend configuration for Private Link (Confluent Cloud)
  frontend_ip_configuration {
    name                          = "appgw-frontend-private"
    subnet_id                     = azurerm_subnet.appgw.id
    private_ip_address            = cidrhost(var.appgw_subnet_prefix, 10)
    private_ip_address_allocation = "Static"
    private_link_configuration_name = "private-link-config"
  }

  # Frontend port for IBM MQ
  frontend_port {
    name = "ibm-mq-port"
    port = var.ibm_mq_frontend_port
  }

  # Backend address pool for IBM MQ servers
  backend_address_pool {
    name  = "ibm-mq-backend-pool"
    fqdns = [for target in var.ibm_mq_backend_targets : target if can(regex("^[a-zA-Z]", target))]
    ip_addresses = [for target in var.ibm_mq_backend_targets : target if can(regex("^[0-9]", target))]
  }

  # Backend settings for IBM MQ
  backend_http_settings {
    name                                = "ibm-mq-backend-settings"
    cookie_based_affinity               = "Disabled"
    port                                = var.ibm_mq_backend_port
    protocol                            = "Http"
    request_timeout                     = 60
    probe_name                          = "ibm-mq-health-probe"
    pick_host_name_from_backend_address = false
  }

  # Health probe for IBM MQ
  # Note: Using Http as Terraform provider doesn't support Tcp yet
  # Will be updated to TCP via Azure CLI post-deployment
  probe {
    name                                      = "ibm-mq-health-probe"
    protocol                                  = "Http"
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = false
    host                                      = "127.0.0.1"
    port                                      = var.ibm_mq_backend_port
  }

  # Listener on private frontend for Confluent Cloud Private Link
  # Note: Terraform provider doesn't support 'Tls' protocol yet for TCP/TLS proxy
  # Using Http for now - for full TCP/TLS proxy, configure via Azure Portal/CLI after deployment
  http_listener {
    name                           = "ibm-mq-private-listener"
    frontend_ip_configuration_name = "appgw-frontend-private"
    frontend_port_name             = "ibm-mq-port"
    protocol                       = "Http"
  }

  # Listener on public frontend (for testing)
  http_listener {
    name                           = "ibm-mq-public-listener"
    frontend_ip_configuration_name = "appgw-frontend-public"
    frontend_port_name             = "ibm-mq-port"
    protocol                       = "Http"
  }

  # Routing rule from private listener to IBM MQ backend
  request_routing_rule {
    name                       = "ibm-mq-private-routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "ibm-mq-private-listener"
    backend_address_pool_name  = "ibm-mq-backend-pool"
    backend_http_settings_name = "ibm-mq-backend-settings"
    priority                   = 100
  }

  # Routing rule from public listener to IBM MQ backend
  request_routing_rule {
    name                       = "ibm-mq-public-routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "ibm-mq-public-listener"
    backend_address_pool_name  = "ibm-mq-backend-pool"
    backend_http_settings_name = "ibm-mq-backend-settings"
    priority                   = 110
  }

  # Private Link configuration for Confluent Cloud
  private_link_configuration {
    name = "private-link-config"

    ip_configuration {
      name                          = "private-link-ip-config"
      subnet_id                     = azurerm_subnet.appgw.id
      private_ip_address_allocation = "Dynamic"
      primary                       = true
    }
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.appgw
  ]
}
