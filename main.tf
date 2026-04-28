# Data source for existing resource group
data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1
  name  = var.existing_resource_group_name
}

# Resource Group - Create new or use existing
resource "azurerm_resource_group" "main" {
  count    = var.create_resource_group ? 1 : 0
  name     = "${var.resource_prefix}-rg"
  location = var.location
  tags     = var.tags
}

# Local values to reference the correct resource group
locals {
  resource_group_name      = var.create_resource_group ? azurerm_resource_group.main[0].name : data.azurerm_resource_group.existing[0].name
  resource_group_location  = var.create_resource_group ? azurerm_resource_group.main[0].location : data.azurerm_resource_group.existing[0].location
  vnet_resource_group_name = var.existing_vnet_resource_group_name != "" ? var.existing_vnet_resource_group_name : local.resource_group_name
}

# Data source for existing VNet
data "azurerm_virtual_network" "existing" {
  count               = var.create_vnet ? 0 : 1
  name                = var.existing_vnet_name
  resource_group_name = local.vnet_resource_group_name
}

# Virtual Network - Create new or use existing
resource "azurerm_virtual_network" "main" {
  count               = var.create_vnet ? 1 : 0
  name                = "${var.resource_prefix}-vnet"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# Local values to reference the correct VNet
locals {
  vnet_name = var.create_vnet ? azurerm_virtual_network.main[0].name : data.azurerm_virtual_network.existing[0].name
  vnet_id   = var.create_vnet ? azurerm_virtual_network.main[0].id : data.azurerm_virtual_network.existing[0].id
}

# Data sources for existing subnets
data "azurerm_subnet" "existing_appgw" {
  count                = var.create_subnets ? 0 : 1
  name                 = var.existing_appgw_subnet_name
  virtual_network_name = local.vnet_name
  resource_group_name  = local.vnet_resource_group_name
}

# Subnet for Application Gateway - Create new or use existing
resource "azurerm_subnet" "appgw" {
  count                                         = var.create_subnets ? 1 : 0
  name                                          = "${var.resource_prefix}-appgw-subnet"
  resource_group_name                           = local.vnet_resource_group_name
  virtual_network_name                          = local.vnet_name
  address_prefixes                              = [var.appgw_subnet_prefix]
  private_link_service_network_policies_enabled = false
}

# Local values to reference the correct subnet
locals {
  appgw_subnet_id = var.create_subnets ? azurerm_subnet.appgw[0].id : data.azurerm_subnet.existing_appgw[0].id
}

# Network Security Group removed - not required for Application Gateway
# Application Gateway manages its own security requirements

# Public IP for Application Gateway
resource "azurerm_public_ip" "appgw" {
  name                = "${var.resource_prefix}-appgw-pip"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Application Gateway with native TCP/TLS proxy support for IBM MQ
# Uses Terraform-native listener, backend_settings, and routing_rule blocks
resource "azurerm_application_gateway" "main" {
  name                = "${var.resource_prefix}-appgw"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  tags                = var.tags

  sku {
    name     = var.appgw_sku.name
    tier     = var.appgw_sku.tier
    capacity = var.appgw_sku.capacity
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = local.appgw_subnet_id
  }

  # Frontend configuration for public access
  frontend_ip_configuration {
    name                 = "appgw-frontend-public"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  # Frontend configuration for Private Link (Confluent Cloud)
  # Note: Application Gateway Standard_v2 with Private Link REQUIRES static IP allocation
  frontend_ip_configuration {
    name                            = "appgw-frontend-private"
    subnet_id                       = local.appgw_subnet_id
    private_ip_address              = cidrhost(var.appgw_subnet_prefix, 50)
    private_ip_address_allocation   = "Static"
    private_link_configuration_name = "private-link-config"
  }

  # Frontend port for IBM MQ
  frontend_port {
    name = "ibm-mq-port"
    port = var.ibm_mq_frontend_port
  }

  # Backend address pool for IBM MQ servers
  backend_address_pool {
    name         = "ibm-mq-backend-pool"
    fqdns        = [for target in var.ibm_mq_backend_targets : target if can(regex("^[a-zA-Z]", target))]
    ip_addresses = [for target in var.ibm_mq_backend_targets : target if can(regex("^[0-9]", target))]
  }

  # TCP Health probe for IBM MQ
  probe {
    name                = "ibm-mq-health-probe"
    protocol            = "Tcp"
    port                = var.ibm_mq_backend_port
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }

  # TCP Backend settings for IBM MQ
  backend {
    name               = "ibm-mq-backend-settings"
    port               = var.ibm_mq_backend_port
    protocol           = "Tcp"
    timeout_in_seconds = 20
    probe_name         = "ibm-mq-health-probe"
  }

  # TCP Listener on private frontend for Confluent Cloud Private Link
  listener {
    name                           = "ibm-mq-listener"
    protocol                       = "Tcp"
    frontend_ip_configuration_name = "appgw-frontend-private"
    frontend_port_name             = "ibm-mq-port"
  }

  # TCP Routing rule from listener to IBM MQ backend
  routing_rule {
    name                      = "ibm-mq-routing-rule"
    priority                  = 100
    listener_name             = "ibm-mq-listener"
    backend_address_pool_name = "ibm-mq-backend-pool"
    backend_name              = "ibm-mq-backend-settings"
  }

  # ===== Oracle XStream Configuration (Optional) =====
  # Frontend port for Oracle (1521) - only created if Oracle targets are configured
  dynamic "frontend_port" {
    for_each = length(var.oracle_backend_targets) > 0 ? [1] : []
    content {
      name = "oracle-port"
      port = var.oracle_frontend_port
    }
  }

  # Backend address pool for Oracle servers
  dynamic "backend_address_pool" {
    for_each = length(var.oracle_backend_targets) > 0 ? [1] : []
    content {
      name         = "oracle-backend-pool"
      fqdns        = [for target in var.oracle_backend_targets : target if can(regex("^[a-zA-Z]", target))]
      ip_addresses = [for target in var.oracle_backend_targets : target if can(regex("^[0-9]", target))]
    }
  }

  # TCP Health probe for Oracle
  dynamic "probe" {
    for_each = length(var.oracle_backend_targets) > 0 ? [1] : []
    content {
      name                = "oracle-health-probe"
      protocol            = "Tcp"
      port                = var.oracle_backend_port
      interval            = 30
      timeout             = 30
      unhealthy_threshold = 3
    }
  }

  # TCP Backend settings for Oracle
  dynamic "backend" {
    for_each = length(var.oracle_backend_targets) > 0 ? [1] : []
    content {
      name               = "oracle-backend-settings"
      port               = var.oracle_backend_port
      protocol           = "Tcp"
      timeout_in_seconds = 20
      probe_name         = "oracle-health-probe"
    }
  }

  # TCP Listener for Oracle
  dynamic "listener" {
    for_each = length(var.oracle_backend_targets) > 0 ? [1] : []
    content {
      name                           = "oracle-listener"
      protocol                       = "Tcp"
      frontend_ip_configuration_name = "appgw-frontend-private"
      frontend_port_name             = "oracle-port"
    }
  }

  # TCP Routing rule from listener to Oracle backend
  dynamic "routing_rule" {
    for_each = length(var.oracle_backend_targets) > 0 ? [1] : []
    content {
      name                      = "oracle-routing-rule"
      priority                  = 200 # Different priority from IBM MQ (100)
      listener_name             = "oracle-listener"
      backend_address_pool_name = "oracle-backend-pool"
      backend_name              = "oracle-backend-settings"
    }
  }

  # Private Link configuration for Confluent Cloud
  private_link_configuration {
    name = "private-link-config"

    ip_configuration {
      name                          = "private-link-ip-config"
      subnet_id                     = local.appgw_subnet_id
      private_ip_address_allocation = "Dynamic"
      primary                       = true
    }
  }
}

# ===== Oracle Database Provisioning (Optional) =====
# Provisions Oracle XE 21c in Docker on Azure VM
# Only created if provision_oracle_database = true

module "oracle_database" {
  count  = var.provision_oracle_database ? 1 : 0
  source = "./modules/oracle-database/terraform"

  resource_prefix     = var.resource_prefix
  resource_group_name = local.resource_group_name
  vnet_name           = local.vnet_name
  appgw_subnet_prefix = var.appgw_subnet_prefix

  # SSH Configuration
  ssh_public_key       = var.oracle_ssh_public_key
  ssh_private_key_path = var.oracle_ssh_private_key_path

  # Oracle Configuration
  oracle_sys_password = var.oracle_sys_password
  oracle_pdb_name     = var.oracle_pdb_name
  vm_size             = var.oracle_vm_size
  configure_xstream   = true

  tags = var.tags

  depends_on = [
    azurerm_virtual_network.main,
    azurerm_subnet.appgw
  ]
}
