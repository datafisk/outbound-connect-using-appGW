# OCI Oracle RAC Terraform Module

This Terraform module deploys a 2-node Oracle Real Application Clusters (RAC) database on Oracle Cloud Infrastructure using the Base Database Service.

## Features

- ✅ **2-Node RAC Cluster** - True active-active multi-instance RAC
- ✅ **Fully Managed** - OCI manages patching, backups, monitoring
- ✅ **ASM Storage** - Automatic Storage Management for shared storage
- ✅ **Automated Deployment** - Complete setup in 60-120 minutes
- ✅ **XStream CDC Ready** - Pre-configured for Confluent Oracle CDC connector
- ✅ **Cost Effective** - ~$435-800/month depending on license model

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ OCI Virtual Cloud Network (VCN)                            │
│                                                              │
│  ┌──────────────────────────┐  ┌──────────────────────────┐│
│  │ Client Subnet            │  │ Backup Subnet            ││
│  │ 10.0.1.0/24              │  │ 10.0.2.0/24              ││
│  │                          │  │                          ││
│  │  ┌───────────────────┐   │  │  ┌───────────────────┐  ││
│  │  │ RAC Node 1        │   │  │  │ Backup NIC        │  ││
│  │  │ - Public IP       │   │  │  │                   │  ││
│  │  │ - Private IP      │   │  │  │                   │  ││
│  │  │ - VIP             │   │  │  │                   │  ││
│  │  └───────────────────┘   │  │  └───────────────────┘  ││
│  │                          │  │                          ││
│  │  ┌───────────────────┐   │  │  ┌───────────────────┐  ││
│  │  │ RAC Node 2        │   │  │  │ Backup NIC        │  ││
│  │  │ - Public IP       │   │  │  │                   │  ││
│  │  │ - Private IP      │   │  │  │                   │  ││
│  │  │ - VIP             │   │  │  │                   │  ││
│  │  └───────────────────┘   │  │  └───────────────────┘  ││
│  │                          │  │                          ││
│  │  ┌───────────────────┐   │  │                          ││
│  │  │ SCAN IP (x3)      │   │  │                          ││
│  │  │ - Load balances   │   │  │                          ││
│  │  │   connections     │   │  │                          ││
│  │  └───────────────────┘   │  │                          ││
│  └──────────────────────────┘  └──────────────────────────┘│
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Shared ASM Storage                                   │   │
│  │ - OCR (Oracle Cluster Registry)                      │   │
│  │ - Voting Disks                                       │   │
│  │ - DATA Disk Group                                    │   │
│  │ - RECO Disk Group (backups)                          │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **OCI Account** - with permissions to create DB Systems
2. **OCI CLI** - installed and configured (`oci setup config`)
3. **Terraform** - version 1.0 or higher
4. **SSH Key Pair** - for accessing RAC nodes
5. **Compartment OCID** - where resources will be created
6. **Availability Domain** - where DB system will be deployed

## Quick Start

### 1. Install OCI CLI

```bash
# macOS
brew install oci-cli

# Configure authentication
oci setup config
```

### 2. Get Required OCIDs

```bash
# Get compartment OCID
oci iam compartment list --all --output table

# Get availability domain
oci iam availability-domain list --output table
```

### 3. Configure Terraform

```bash
# Copy example configuration
cp terraform.tfvars.oci-example terraform.tfvars

# Edit terraform.tfvars with your values
vi terraform.tfvars
```

Required values:
- `compartment_id` - Your compartment OCID
- `availability_domain` - AD name (e.g., "AD-1")
- `db_admin_password` - Strong password for SYS/SYSTEM
- `ssh_public_key` - Your SSH public key

### 4. Deploy

```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan

# Deploy (takes 60-120 minutes)
terraform apply
```

### 5. Access Your RAC Cluster

```bash
# Get connection information
terraform output deployment_summary

# SSH to nodes
ssh -i ~/.ssh/id_rsa opc@<node-ip>

# Check cluster status
sudo su - grid
crsctl status resource -t

# Check database status
srvctl status database -d RACDB
```

## Module Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| compartment_id | OCID of compartment | string | - | yes |
| availability_domain | AD name (e.g., "AD-1") | string | - | yes |
| db_admin_password | Database admin password | string | - | yes |
| ssh_public_key | SSH public key | string | - | yes |
| name_prefix | Resource name prefix | string | "oracle-rac" | no |
| db_system_shape | VM shape | string | "VM.Standard2.4" | no |
| data_storage_size_gb | Storage size in GB | number | 512 | no |
| db_name | Database name | string | "RACDB" | no |
| pdb_name | PDB name | string | "PDB1" | no |
| license_model | LICENSE_INCLUDED or BYOL | string | "BRING_YOUR_OWN_LICENSE" | no |

See [variables.tf](variables.tf) for complete list.

## Module Outputs

| Name | Description |
|------|-------------|
| db_system_id | OCID of DB System |
| scan_dns_name | SCAN DNS name for connections |
| database_connection_string | Full connection string |
| deployment_summary | Summary of deployment |
| next_steps | Instructions for next steps |

## Cost Estimation

Based on default configuration (VM.Standard2.4, 512 GB storage, BYOL):

| Component | Monthly Cost |
|-----------|--------------|
| Compute (2 nodes) | ~$350 |
| Storage (512 GB) | ~$50 |
| Backups (7 days) | ~$25 |
| Network | ~$10 |
| **Total (BYOL)** | **~$435** |
| **Total (License Included)** | **~$800** |

Costs vary by region and configuration. Check [OCI Pricing](https://www.oracle.com/cloud/price-list.html).

## Cleanup

```bash
# Destroy all resources
terraform destroy
```

This will delete:
- DB System (both nodes)
- All storage
- VCN and networking
- Everything created by Terraform

## Troubleshooting

### Error: "NotAuthorizedOrNotFound"

Check compartment OCID and user permissions:
```bash
oci iam compartment get --compartment-id <ocid>
```

### Error: "Shape VM.Standard2.4 is not available"

List available shapes:
```bash
oci db system-shape list --compartment-id <ocid> --availability-domain <ad> --output table
```

### Error: "Limit exceeded"

Check and request limit increase:
```bash
oci limits value list --compartment-id <tenancy-ocid> --service-name compute
```

## Additional Resources

- [OCI Database Service Documentation](https://docs.oracle.com/en-us/iaas/Content/Database/home.htm)
- [OCI Terraform Provider](https://registry.terraform.io/providers/oracle/oci/latest/docs)
- [Oracle RAC on OCI Best Practices](https://docs.oracle.com/en/solutions/deploy-oracle-db-rac-oci/)
- [XStream CDC Configuration Guide](../OCI-GETTING-STARTED.md#step-5-configure-xstream-cdc)

## License

This module deploys Oracle Database software. Ensure you have appropriate Oracle licenses or use LICENSE_INCLUDED option.

## Support

For issues with this Terraform module, please create an issue in the repository.

For Oracle Database support, contact Oracle Support if you have a support contract.
