# Oracle Database (XE 21c) on Azure VM with Docker
# This module provisions an Oracle XE 21c database in a Docker container on an Azure VM

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.67"
    }
  }
}

# Data source for existing resource group
data "azurerm_resource_group" "oracle" {
  name = var.resource_group_name
}

# Data source for existing VNet
data "azurerm_virtual_network" "oracle" {
  name                = var.vnet_name
  resource_group_name = var.vnet_resource_group_name != "" ? var.vnet_resource_group_name : var.resource_group_name
}

# Subnet for Oracle VM
resource "azurerm_subnet" "oracle" {
  count                = var.create_subnet ? 1 : 0
  name                 = "${var.resource_prefix}-oracle-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.vnet_name
  address_prefixes     = [var.oracle_subnet_prefix]
}

# Network Security Group for Oracle
# Only created if create_nsg is true (skip when using existing subnet with existing NSG)
resource "azurerm_network_security_group" "oracle" {
  count               = var.create_nsg ? 1 : 0
  name                = "${var.resource_prefix}-oracle-nsg"
  location            = data.azurerm_resource_group.oracle.location
  resource_group_name = var.resource_group_name

  # SSH access
  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_ssh_cidr
    destination_address_prefix = "*"
  }

  # Oracle Database access from App Gateway subnet (if appgw_subnet_prefix provided)
  dynamic "security_rule" {
    for_each = var.appgw_subnet_prefix != "" ? [1] : []
    content {
      name                       = "Oracle"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "1521"
      source_address_prefix      = var.appgw_subnet_prefix
      destination_address_prefix = "*"
    }
  }

  tags = var.tags
}

# Public IP for Oracle VM (for SSH access)
resource "azurerm_public_ip" "oracle" {
  count               = var.create_public_ip ? 1 : 0
  name                = "${var.resource_prefix}-oracle-pip"
  location            = data.azurerm_resource_group.oracle.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Network Interface for Oracle VM
resource "azurerm_network_interface" "oracle" {
  name                = "${var.resource_prefix}-oracle-nic"
  location            = data.azurerm_resource_group.oracle.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.create_subnet ? azurerm_subnet.oracle[0].id : var.existing_subnet_id
    private_ip_address_allocation = var.oracle_private_ip != "" ? "Static" : "Dynamic"
    private_ip_address            = var.oracle_private_ip != "" ? var.oracle_private_ip : null
    public_ip_address_id          = var.create_public_ip ? azurerm_public_ip.oracle[0].id : null
  }

  tags = var.tags
}

# Associate NSG with NIC (only if NSG was created)
resource "azurerm_network_interface_security_group_association" "oracle" {
  count                     = var.create_nsg ? 1 : 0
  network_interface_id      = azurerm_network_interface.oracle.id
  network_security_group_id = azurerm_network_security_group.oracle[0].id
}

# Azure VM for Oracle Database
resource "azurerm_linux_virtual_machine" "oracle" {
  name                            = "${var.resource_prefix}-oracle-vm"
  resource_group_name             = var.resource_group_name
  location                        = data.azurerm_resource_group.oracle.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.oracle.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Cloud-init configuration to install Docker and Oracle
  custom_data = base64encode(templatefile("${path.module}/../scripts/cloud-init.yaml", {
    oracle_password      = var.oracle_sys_password
    oracle_pdb           = var.oracle_pdb_name
    oracle_characterset  = var.oracle_characterset
    oracle_memory_mb     = var.oracle_memory_mb
    enable_archivelog    = var.enable_archivelog
  }))

  tags = merge(var.tags, {
    Component = "Oracle Database"
  })
}

# Wait for Oracle to be ready
resource "null_resource" "wait_for_oracle" {
  depends_on = [azurerm_linux_virtual_machine.oracle]

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for Oracle Database to start...'",
      "timeout 600 bash -c 'until docker logs oracle21c 2>&1 | grep -q \"DATABASE IS READY TO USE\"; do sleep 10; done'",
      "echo 'Oracle Database is ready!'"
    ]

    connection {
      type        = "ssh"
      user        = var.admin_username
      private_key = file(var.ssh_private_key_path)
      host        = var.create_public_ip ? azurerm_public_ip.oracle[0].ip_address : azurerm_network_interface.oracle.private_ip_address
    }
  }
}

# Setup Oracle for XStream CDC
resource "null_resource" "setup_xstream" {
  count      = var.configure_xstream ? 1 : 0
  depends_on = [null_resource.wait_for_oracle]

  provisioner "file" {
    source      = "${path.module}/../scripts"
    destination = "/tmp/oracle-setup"

    connection {
      type        = "ssh"
      user        = var.admin_username
      private_key = file(var.ssh_private_key_path)
      host        = var.create_public_ip ? azurerm_public_ip.oracle[0].ip_address : azurerm_network_interface.oracle.private_ip_address
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/oracle-setup/*.sh",
      "cd /tmp/oracle-setup",
      "./00_setup_cdc.sh ${var.oracle_sys_password} ${var.oracle_pdb_name}"
    ]

    connection {
      type        = "ssh"
      user        = var.admin_username
      private_key = file(var.ssh_private_key_path)
      host        = var.create_public_ip ? azurerm_public_ip.oracle[0].ip_address : azurerm_network_interface.oracle.private_ip_address
    }
  }
}
