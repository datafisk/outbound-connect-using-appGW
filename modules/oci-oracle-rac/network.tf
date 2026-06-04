# Data source for existing VCN (if using existing)
data "oci_core_vcn" "existing_vcn" {
  count  = var.use_existing_vcn ? 1 : 0
  vcn_id = var.existing_vcn_id
}

# Data source for existing client subnet (if using existing)
data "oci_core_subnet" "existing_client_subnet" {
  count     = var.use_existing_client_subnet ? 1 : 0
  subnet_id = var.existing_client_subnet_id
}

# Create new VCN (only if not using existing)
resource "oci_core_vcn" "rac_vcn" {
  count = var.use_existing_vcn ? 0 : 1

  compartment_id = var.compartment_id
  display_name   = "${var.name_prefix}-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = var.vcn_dns_label

  freeform_tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-vcn"
    }
  )
}

# Local variable to reference VCN (existing or new)
locals {
  vcn_id = var.use_existing_vcn ? data.oci_core_vcn.existing_vcn[0].id : oci_core_vcn.rac_vcn[0].id
}

# Internet Gateway (only create if creating new VCN)
resource "oci_core_internet_gateway" "rac_igw" {
  count = var.use_existing_vcn ? 0 : 1

  compartment_id = var.compartment_id
  vcn_id         = local.vcn_id
  display_name   = "${var.name_prefix}-igw"
  enabled        = true

  freeform_tags = var.tags
}

# Route Table (only create if creating new VCN)
resource "oci_core_route_table" "rac_public_rt" {
  count = var.use_existing_vcn ? 0 : 1

  compartment_id = var.compartment_id
  vcn_id         = local.vcn_id
  display_name   = "${var.name_prefix}-public-rt"

  route_rules {
    network_entity_id = oci_core_internet_gateway.rac_igw[0].id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }

  freeform_tags = var.tags
}

# Security List (only create if creating new VCN)
resource "oci_core_security_list" "rac_security_list" {
  count = var.use_existing_vcn ? 0 : 1

  compartment_id = var.compartment_id
  vcn_id         = local.vcn_id
  display_name   = "${var.name_prefix}-security-list"

  # Egress Rules - Allow all outbound
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
  }

  # Ingress Rules - SSH (22)
  ingress_security_rules {
    protocol  = "6" # TCP
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      min = 22
      max = 22
    }
  }

  # Ingress Rules - Oracle Listener (1521)
  ingress_security_rules {
    protocol  = "6" # TCP
    source    = var.vcn_cidr
    stateless = false

    tcp_options {
      min = 1521
      max = 1521
    }
  }

  # Ingress Rules - Oracle Enterprise Manager (5500)
  ingress_security_rules {
    protocol  = "6" # TCP
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      min = 5500
      max = 5500
    }
  }

  # Ingress Rules - All traffic within VCN (for RAC interconnect)
  ingress_security_rules {
    protocol  = "all"
    source    = var.vcn_cidr
    stateless = false
  }

  # Ingress Rules - ICMP for ping
  ingress_security_rules {
    protocol  = "1" # ICMP
    source    = "0.0.0.0/0"
    stateless = false
  }

  freeform_tags = var.tags
}

# Create client subnet (only if not using existing)
resource "oci_core_subnet" "rac_client_subnet" {
  count = var.use_existing_client_subnet ? 0 : 1

  compartment_id             = var.compartment_id
  vcn_id                     = local.vcn_id
  display_name               = "${var.name_prefix}-client-subnet"
  cidr_block                 = var.client_subnet_cidr
  route_table_id             = var.use_existing_vcn ? null : oci_core_route_table.rac_public_rt[0].id
  security_list_ids          = var.use_existing_vcn ? null : [oci_core_security_list.rac_security_list[0].id]
  dns_label                  = "client"
  prohibit_public_ip_on_vnic = false
  prohibit_internet_ingress  = false

  freeform_tags = var.tags
}

# Local variable to reference client subnet (existing or new)
locals {
  client_subnet_id = var.use_existing_client_subnet ? data.oci_core_subnet.existing_client_subnet[0].id : oci_core_subnet.rac_client_subnet[0].id
}

# Always create backup subnet (required for Oracle RAC)
resource "oci_core_subnet" "rac_backup_subnet" {
  compartment_id             = var.compartment_id
  vcn_id                     = local.vcn_id
  display_name               = "${var.name_prefix}-backup-subnet"
  cidr_block                 = var.backup_subnet_cidr
  route_table_id             = var.use_existing_vcn ? null : oci_core_route_table.rac_public_rt[0].id
  security_list_ids          = var.use_existing_vcn ? null : [oci_core_security_list.rac_security_list[0].id]
  dns_label                  = "backup"
  prohibit_public_ip_on_vnic = false
  prohibit_internet_ingress  = false

  freeform_tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-backup-subnet"
    }
  )
}
