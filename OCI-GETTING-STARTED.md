# Oracle Cloud Infrastructure (OCI) - Getting Started Guide

**Date:** 2026-05-20  
**Purpose:** Set up OCI CLI and Terraform for Oracle RAC deployment

---

## Overview

Oracle Cloud Infrastructure provides both CLI and Terraform support similar to Azure:

| Tool | OCI Command | Azure Equivalent | Purpose |
|------|-------------|------------------|---------|
| **CLI** | `oci` | `az` | Interactive management, scripting |
| **Terraform** | `terraform` with OCI provider | `terraform` with AzureRM provider | Infrastructure-as-code |
| **Web Console** | https://cloud.oracle.com | https://portal.azure.com | GUI management |

**Key Differences from Azure:**
- OCI uses **API keys** (public/private key pairs) instead of interactive login
- OCI organizes resources by **Compartment** (similar to Azure Resource Groups)
- OCI networking uses **VCN** (Virtual Cloud Network) instead of VNet
- OCI has native **DB Systems** service for managed Oracle databases

---

## Step 1: Create OCI Account

### Free Tier Option (Recommended for Testing)
1. Go to https://www.oracle.com/cloud/free/
2. Click **Start for free**
3. Fill in details (email, country, etc.)
4. Verify email and complete registration
5. **Free tier includes:**
   - $300 USD free credits for 30 days
   - Always Free services (limited compute, storage, databases)
   - Can run small DB system for testing

### Paid Account
1. Go to https://cloud.oracle.com
2. Sign up with credit card
3. Choose region (home region cannot be changed later)

---

## Step 2: Install OCI CLI

The OCI CLI is similar to Azure `az` command.

### macOS Installation (Homebrew - Recommended)

```bash
# Install OCI CLI
brew install oci-cli

# Verify installation
oci --version

# Expected output: oci-cli/<version>
```

### Alternative: Python pip Installation

```bash
# Install via pip (works on macOS, Linux, Windows)
pip install oci-cli

# Or use the installer script
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"

# Verify
oci --version
```

### Linux Installation

```bash
# Download and run installer
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"

# Add to PATH (if not already)
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify
oci --version
```

---

## Step 3: Configure OCI CLI Authentication

OCI uses API keys (RSA key pairs) for authentication, unlike Azure's interactive login.

### Interactive Setup (Easiest)

```bash
# Run interactive setup - will guide you through configuration
oci setup config

# You'll be asked for:
# 1. Location for config file [~/.oci/config]: <press Enter>
# 2. User OCID: <copy from OCI Console>
# 3. Tenancy OCID: <copy from OCI Console>
# 4. Region: <e.g., us-ashburn-1>
# 5. Generate new RSA key pair? [Y/n]: Y
# 6. Directory for keys [~/.oci]: <press Enter>
# 7. Key name [oci_api_key]: <press Enter>
```

### Where to Find OCIDs (Oracle Cloud IDs)

1. **Log into OCI Console:** https://cloud.oracle.com
2. **User OCID:**
   - Click your profile icon (top right)
   - Click **User Settings**
   - Copy **OCID** under User Information
   - Format: `ocid1.user.oc1..aaaaa...`

3. **Tenancy OCID:**
   - Click your profile icon (top right)
   - Click **Tenancy: <your-tenancy-name>**
   - Copy **OCID** under Tenancy Information
   - Format: `ocid1.tenancy.oc1..aaaaa...`

4. **Region:**
   - Choose your home region (e.g., `us-ashburn-1`, `us-phoenix-1`, `eu-frankfurt-1`)
   - List available regions: https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm

### Manual Setup

If you prefer manual configuration:

```bash
# Create OCI config directory
mkdir -p ~/.oci

# Generate API key pair
openssl genrsa -out ~/.oci/oci_api_key.pem 2048
openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem

# Set proper permissions
chmod 600 ~/.oci/oci_api_key.pem
chmod 644 ~/.oci/oci_api_key_public.pem

# Create config file
cat > ~/.oci/config << 'EOF'
[DEFAULT]
user=<your-user-ocid>
fingerprint=<will-add-after-upload>
tenancy=<your-tenancy-ocid>
region=<your-region>
key_file=~/.oci/oci_api_key.pem
EOF
```

### Upload API Public Key to OCI Console

1. Go to **Profile → User Settings → API Keys**
2. Click **Add API Key**
3. Choose **Paste Public Key**
4. Paste contents of `~/.oci/oci_api_key_public.pem`:
   ```bash
   cat ~/.oci/oci_api_key_public.pem
   ```
5. Click **Add**
6. Copy the **Fingerprint** shown
7. Update `~/.oci/config` with the fingerprint

### Test OCI CLI

```bash
# List available regions
oci iam region list --output table

# List compartments in your tenancy
oci iam compartment list --output table

# Get current user info
oci iam user get --user-id <your-user-ocid>

# If these work, authentication is successful! ✅
```

---

## Step 4: Install and Configure Terraform for OCI

### Install Terraform (if not already installed)

```bash
# macOS
brew install terraform

# Verify
terraform --version

# Expected: Terraform v1.x.x or higher
```

### OCI Terraform Provider

The OCI Terraform provider is similar to AzureRM provider.

**Provider Documentation:** https://registry.terraform.io/providers/oracle/oci/latest/docs

**Key Comparison:**

| Azure | OCI | Purpose |
|-------|-----|---------|
| `azurerm` provider | `oci` provider | Cloud provider |
| Resource Group | Compartment | Resource organization |
| `az login` | API key in `~/.oci/config` | Authentication |
| `az account set` | `compartment_id` in Terraform | Scope selection |

---

## Step 5: Create Terraform Configuration for OCI

Let me create a Terraform module structure similar to the Azure one.

### Directory Structure

```
modules/
  oci-oracle-rac/
    main.tf              # Main resources
    variables.tf         # Input variables
    outputs.tf           # Output values
    provider.tf          # OCI provider configuration
    network.tf           # VCN, subnets, security lists
    db-system.tf         # Oracle DB System with RAC
    
terraform.tfvars         # Your configuration values
main.tf                  # Root module
```

---

## Step 6: Example Terraform Code for OCI RAC

### Provider Configuration (`modules/oci-oracle-rac/provider.tf`)

```hcl
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }
}

provider "oci" {
  # Authentication automatically uses ~/.oci/config [DEFAULT] profile
  # Or you can specify:
  # tenancy_ocid     = var.tenancy_ocid
  # user_ocid        = var.user_ocid
  # fingerprint      = var.fingerprint
  # private_key_path = var.private_key_path
  # region           = var.region
}
```

### Network Configuration (`modules/oci-oracle-rac/network.tf`)

```hcl
# Virtual Cloud Network (VCN) - similar to Azure VNet
resource "oci_core_vcn" "rac_vcn" {
  compartment_id = var.compartment_id
  display_name   = "${var.name_prefix}-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = var.vcn_dns_label
}

# Internet Gateway - for public access
resource "oci_core_internet_gateway" "rac_igw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.rac_vcn.id
  display_name   = "${var.name_prefix}-igw"
  enabled        = true
}

# Route Table - for public subnet
resource "oci_core_route_table" "rac_public_rt" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.rac_vcn.id
  display_name   = "${var.name_prefix}-public-rt"

  route_rules {
    network_entity_id = oci_core_internet_gateway.rac_igw.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

# Security List - similar to Azure NSG
resource "oci_core_security_list" "rac_security_list" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.rac_vcn.id
  display_name   = "${var.name_prefix}-security-list"

  # Egress - allow all outbound
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  # Ingress - SSH
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # Ingress - Oracle Listener
  ingress_security_rules {
    protocol = "6" # TCP
    source   = var.vcn_cidr
    tcp_options {
      min = 1521
      max = 1521
    }
  }

  # Ingress - All traffic within VCN (for RAC intercommunication)
  ingress_security_rules {
    protocol = "all"
    source   = var.vcn_cidr
  }
}

# Client Subnet - for database clients
resource "oci_core_subnet" "rac_client_subnet" {
  compartment_id      = var.compartment_id
  vcn_id              = oci_core_vcn.rac_vcn.id
  display_name        = "${var.name_prefix}-client-subnet"
  cidr_block          = var.client_subnet_cidr
  route_table_id      = oci_core_route_table.rac_public_rt.id
  security_list_ids   = [oci_core_security_list.rac_security_list.id]
  dns_label           = "client"
  prohibit_public_ip_on_vnic = false
}

# Backup Subnet - for database backups
resource "oci_core_subnet" "rac_backup_subnet" {
  compartment_id      = var.compartment_id
  vcn_id              = oci_core_vcn.rac_vcn.id
  display_name        = "${var.name_prefix}-backup-subnet"
  cidr_block          = var.backup_subnet_cidr
  route_table_id      = oci_core_route_table.rac_public_rt.id
  security_list_ids   = [oci_core_security_list.rac_security_list.id]
  dns_label           = "backup"
  prohibit_public_ip_on_vnic = false
}
```

### DB System with RAC (`modules/oci-oracle-rac/db-system.tf`)

```hcl
# Oracle Database System with 2-Node RAC
resource "oci_database_db_system" "rac_db_system" {
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain
  
  # RAC Configuration
  database_edition        = "ENTERPRISE_EDITION_EXTREME_PERFORMANCE"
  db_system_options {
    storage_management = "ASM" # Automatic Storage Management
  }
  
  # Cluster Configuration
  cluster_name = var.cluster_name
  node_count   = 2  # 2-node RAC cluster
  
  # VM Shape
  shape = var.db_system_shape  # e.g., "VM.Standard2.4"
  
  # Storage
  data_storage_size_in_gb = var.data_storage_size_gb
  
  # Network
  subnet_id        = oci_core_subnet.rac_client_subnet.id
  backup_subnet_id = oci_core_subnet.rac_backup_subnet.id
  hostname         = var.hostname_prefix
  
  # SSH Access
  ssh_public_keys = [var.ssh_public_key]
  
  # Database Configuration
  db_home {
    database {
      admin_password = var.db_admin_password
      db_name        = var.db_name
      pdb_name       = var.pdb_name
      
      db_workload = "OLTP"
      
      # Database Version
      db_version = var.db_version  # e.g., "19.21.0.0"
    }
    
    db_version   = var.db_version
    display_name = "${var.name_prefix}-dbhome"
  }
  
  # License
  license_model = var.license_model  # "LICENSE_INCLUDED" or "BRING_YOUR_OWN_LICENSE"
  
  display_name = "${var.name_prefix}-db-system"
  
  # Tags
  freeform_tags = var.tags
}
```

### Variables (`modules/oci-oracle-rac/variables.tf`)

```hcl
variable "compartment_id" {
  description = "OCID of the compartment where resources will be created"
  type        = string
}

variable "availability_domain" {
  description = "Availability domain for the DB system"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "oracle-rac"
}

variable "vcn_cidr" {
  description = "CIDR block for the VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vcn_dns_label" {
  description = "DNS label for the VCN"
  type        = string
  default     = "racvcn"
}

variable "client_subnet_cidr" {
  description = "CIDR block for client subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "backup_subnet_cidr" {
  description = "CIDR block for backup subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "cluster_name" {
  description = "Name of the RAC cluster"
  type        = string
  default     = "raccluster"
}

variable "hostname_prefix" {
  description = "Hostname prefix for DB nodes"
  type        = string
  default     = "racnode"
}

variable "db_system_shape" {
  description = "Shape for DB system VMs"
  type        = string
  default     = "VM.Standard2.4"
}

variable "data_storage_size_gb" {
  description = "Data storage size in GB"
  type        = number
  default     = 256
}

variable "db_admin_password" {
  description = "Password for SYS/SYSTEM users"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Database name (max 8 chars)"
  type        = string
  default     = "RACDB"
}

variable "pdb_name" {
  description = "Pluggable database name"
  type        = string
  default     = "PDB1"
}

variable "db_version" {
  description = "Oracle Database version"
  type        = string
  default     = "19.21.0.0"
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

variable "license_model" {
  description = "License model: LICENSE_INCLUDED or BRING_YOUR_OWN_LICENSE"
  type        = string
  default     = "BRING_YOUR_OWN_LICENSE"
}

variable "tags" {
  description = "Freeform tags for resources"
  type        = map(string)
  default     = {}
}
```

### Outputs (`modules/oci-oracle-rac/outputs.tf`)

```hcl
output "db_system_id" {
  description = "OCID of the DB system"
  value       = oci_database_db_system.rac_db_system.id
}

output "db_system_scan_dns" {
  description = "SCAN DNS name for RAC cluster"
  value       = oci_database_db_system.rac_db_system.scan_dns_name
}

output "db_system_scan_ips" {
  description = "SCAN IP addresses"
  value       = oci_database_db_system.rac_db_system.scan_ip_ids
}

output "db_node_1_hostname" {
  description = "Hostname of DB node 1"
  value       = "${var.hostname_prefix}1"
}

output "db_node_2_hostname" {
  description = "Hostname of DB node 2"
  value       = "${var.hostname_prefix}2"
}

output "database_connection_string" {
  description = "Database connection string"
  value       = "${oci_database_db_system.rac_db_system.scan_dns_name}:1521/${var.db_name}"
}

output "vcn_id" {
  description = "OCID of the VCN"
  value       = oci_core_vcn.rac_vcn.id
}
```

### Root Module (`main.tf`)

```hcl
module "oci_oracle_rac" {
  source = "./modules/oci-oracle-rac"
  
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain
  
  name_prefix = "confluent-rac"
  
  # Network configuration
  vcn_cidr            = "10.0.0.0/16"
  client_subnet_cidr  = "10.0.1.0/24"
  backup_subnet_cidr  = "10.0.2.0/24"
  
  # RAC cluster configuration
  cluster_name    = "confluentrac"
  hostname_prefix = "racnode"
  
  # VM configuration
  db_system_shape         = "VM.Standard2.4"
  data_storage_size_gb    = 512
  
  # Database configuration
  db_admin_password = var.db_admin_password
  db_name          = "RACDB"
  pdb_name         = "XSTREAMPDB"
  db_version       = "19.21.0.0"
  
  # SSH access
  ssh_public_key = file("~/.ssh/id_rsa.pub")
  
  # License
  license_model = "BRING_YOUR_OWN_LICENSE"  # or "LICENSE_INCLUDED"
  
  tags = {
    Environment = "Test"
    Project     = "Confluent-XStream-CDC"
    ManagedBy   = "Terraform"
  }
}

output "rac_connection_string" {
  value = module.oci_oracle_rac.database_connection_string
}

output "rac_scan_dns" {
  value = module.oci_oracle_rac.db_system_scan_dns
}
```

### Configuration File (`terraform.tfvars`)

```hcl
# OCI Authentication (optional - uses ~/.oci/config by default)
# tenancy_ocid     = "ocid1.tenancy.oc1..aaaaa..."
# user_ocid        = "ocid1.user.oc1..aaaaa..."
# fingerprint      = "xx:xx:xx:..."
# private_key_path = "~/.oci/oci_api_key.pem"
# region           = "us-ashburn-1"

# Resource configuration
compartment_id      = "ocid1.compartment.oc1..aaaaa..."  # Your compartment OCID
availability_domain = "AD-1"  # or "AD-2", "AD-3" depending on region

# Database password (REQUIRED)
db_admin_password = "YourStrongPassword123!"
```

---

## Step 7: Get Required OCIDs

Before running Terraform, you need to get OCIDs for compartment and availability domain.

### Get Compartment OCID

```bash
# List all compartments
oci iam compartment list --all --output table

# Get root compartment (tenancy) OCID
oci iam compartment list --compartment-id-in-subtree true --query "data[?name=='<your-tenancy-name>'].id | [0]" --raw-output

# Create a new compartment for Oracle RAC (recommended)
oci iam compartment create \
  --compartment-id <your-tenancy-ocid> \
  --name "oracle-rac-test" \
  --description "Compartment for Oracle RAC testing"

# Get the new compartment OCID from output
```

### Get Availability Domain

```bash
# List availability domains in your region
oci iam availability-domain list --output table

# Example output:
# +------+------------------+
# | name | id               |
# +------+------------------+
# | AD-1 | ocid1.availa...  |
# | AD-2 | ocid1.availa...  |
# | AD-3 | ocid1.availa...  |
# +------+------------------+

# Use the name (e.g., "AD-1") in terraform.tfvars
```

---

## Step 8: Deploy with Terraform

```bash
# Navigate to project directory
cd /Users/petergustafsson/confluent/outbound-connect-using-appGW

# Initialize Terraform (downloads OCI provider)
terraform init

# Validate configuration
terraform validate

# Plan deployment (see what will be created)
terraform plan

# Review the plan - should show:
# - 1 VCN (Virtual Cloud Network)
# - 1 Internet Gateway
# - 1 Route Table
# - 1 Security List
# - 2 Subnets (client, backup)
# - 1 DB System with 2 nodes (RAC cluster)

# Apply configuration (create resources)
terraform apply

# Type 'yes' when prompted

# Deployment will take 60-120 minutes
# Monitor progress in OCI Console:
# https://cloud.oracle.com → Databases → DB Systems
```

### Monitor Deployment Progress

```bash
# Get DB system OCID from Terraform output
DB_SYSTEM_OCID=$(terraform output -raw rac_db_system_id)

# Check DB system status
oci db system get --db-system-id $DB_SYSTEM_OCID --query "data.\"lifecycle-state\"" --raw-output

# Possible states:
# - PROVISIONING (still creating)
# - AVAILABLE (ready to use) ✅
# - FAILED (something went wrong)

# Watch status (poll every 2 minutes)
watch -n 120 "oci db system get --db-system-id $DB_SYSTEM_OCID --query 'data.\"lifecycle-state\"' --raw-output"
```

---

## Step 9: Access Your RAC Cluster

### Get Connection Information

```bash
# From Terraform outputs
terraform output rac_connection_string
# Example: racscan.racvcn.oraclevcn.com:1521/RACDB

terraform output rac_scan_dns
# Example: racscan.racvcn.oraclevcn.com

# Or use OCI CLI
oci db system get --db-system-id $DB_SYSTEM_OCID --query "data.\"scan-dns-name\"" --raw-output
```

### SSH to RAC Nodes

```bash
# Get node public IPs
oci db node list --compartment-id <your-compartment-ocid> --db-system-id $DB_SYSTEM_OCID --query "data[*].{hostname:hostname,ip:\"public-ip\"}" --output table

# SSH to node 1
ssh -i ~/.ssh/id_rsa opc@<node1-public-ip>

# Check cluster status
sudo su - grid
crsctl status resource -t

# Check database status
srvctl status database -d RACDB
```

---

## Step 10: Clean Up (When Done Testing)

```bash
# Destroy all resources
terraform destroy

# Type 'yes' when prompted

# This will delete:
# - DB System (both nodes)
# - All storage
# - Network resources
# - Everything created by Terraform

# Verify deletion
oci db system list --compartment-id <your-compartment-ocid> --output table
```

---

## Cost Management

### Monitor Costs

```bash
# View cost analysis in OCI Console
# https://cloud.oracle.com → Billing & Cost Management → Cost Analysis

# Or use CLI (requires setup)
oci usage-api usage-summary list --tenant-id <tenancy-ocid> --time-usage-started "<start-date>" --time-usage-ended "<end-date>"
```

### Cost-Saving Tips

1. **Use Always Free Tier** for testing (if eligible)
2. **Stop DB system** when not in use (charges reduced but not eliminated)
   ```bash
   oci db system stop --db-system-id $DB_SYSTEM_OCID
   ```
3. **Destroy resources** when done testing (`terraform destroy`)
4. **Use smaller shapes** for testing (VM.Standard2.2 instead of VM.Standard2.4)
5. **Set budget alerts** in OCI Console

---

## Comparison: OCI vs Azure Workflow

| Task | Azure | OCI |
|------|-------|-----|
| **Install CLI** | `brew install azure-cli` | `brew install oci-cli` |
| **Login** | `az login` (interactive) | `oci setup config` (API key) |
| **List resources** | `az resource list` | `oci db system list` |
| **Terraform provider** | `azurerm` | `oci` |
| **Resource container** | Resource Group | Compartment |
| **Network** | VNet | VCN |
| **Security** | NSG | Security List |
| **CLI config** | `~/.azure/` | `~/.oci/config` |
| **Terraform auth** | `az login` | API key file |

---

## Troubleshooting

### Issue: "Service error: NotAuthorizedOrNotFound"

**Solution:** Check compartment OCID and verify user has permissions

```bash
# Verify compartment exists
oci iam compartment get --compartment-id <your-compartment-ocid>

# Check user permissions
oci iam user list-groups --user-id <your-user-ocid>
```

### Issue: "Shape VM.Standard2.4 is not available"

**Solution:** Check available shapes in your region

```bash
# List available DB system shapes
oci db system-shape list --compartment-id <compartment-ocid> --availability-domain <ad-name> --output table

# Use a different shape in terraform.tfvars
```

### Issue: "Limit exceeded for resource"

**Solution:** Request limit increase or use smaller resources

```bash
# Check service limits
oci limits value list --compartment-id <tenancy-ocid> --service-name compute

# Request limit increase in OCI Console:
# https://cloud.oracle.com → Governance → Limits, Quotas, and Usage
```

### Issue: Terraform state locked

**Solution:** Force unlock (use carefully)

```bash
terraform force-unlock <lock-id>
```

---

## Next Steps

1. ✅ Install OCI CLI: `brew install oci-cli`
2. ✅ Configure authentication: `oci setup config`
3. ✅ Get compartment OCID
4. ✅ Get availability domain name
5. ✅ Create Terraform module (provided above)
6. ✅ Update `terraform.tfvars` with your OCIDs
7. ✅ Run `terraform apply`
8. ⏳ Wait 60-120 minutes for provisioning
9. ✅ Configure XStream CDC
10. ✅ Test Confluent connector

---

## Additional Resources

### Official Documentation
- [OCI CLI Documentation](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/cliconcepts.htm)
- [OCI Terraform Provider](https://registry.terraform.io/providers/oracle/oci/latest/docs)
- [OCI Database Service](https://docs.oracle.com/en-us/iaas/Content/Database/Concepts/overview.htm)
- [OCI Free Tier](https://www.oracle.com/cloud/free/)

### Example Terraform Configurations
- [OCI Terraform Examples on GitHub](https://github.com/oracle/terraform-provider-oci/tree/master/examples)
- [OCI Landing Zones](https://github.com/oracle-quickstart/oci-landing-zones)

### Training
- [OCI Getting Started Tutorial](https://docs.oracle.com/en-us/iaas/Content/GSG/Concepts/baremetalintro.htm)
- [OCI Terraform Workshop](https://oracle.github.io/learning-library/oci-library/oci-hol/oci-terraform/)

---

**Ready to get started?** Install OCI CLI and let me know when you're ready to configure authentication!
