# Oracle RAC Installation and Configuration Guide

This guide walks through deploying a 2-node Oracle Real Application Clusters (RAC) environment on Azure for use with Confluent Oracle XStream CDC connector.

## Why Oracle RAC?

The existing Oracle XStream connector setup uses a **standalone** Oracle database. For production environments requiring:
- **High Availability** - Automatic failover between nodes
- **Scalability** - Load distribution across multiple instances
- **Zero Downtime Maintenance** - Rolling patches and upgrades

Oracle RAC provides a clustered database solution with multiple instances accessing shared storage.

## Current Status: Phase 1 Complete ✅

**What's deployed:**
- ✅ 2 Oracle Linux VMs (Standard_D4s_v3, 4 vCPUs, 16 GB RAM each - PoC optimized)
- ✅ 3-network topology (public, private, interconnect) - works with existing VNets
- ✅ Availability Set for fault domain distribution
- ✅ Accelerated networking optional (disabled by default for PoC cost savings)
- ✅ NSG rules for RAC traffic (optional, can use existing NSGs)
- ✅ Oracle 19c from Azure Marketplace (ready to install)
- ✅ Pre-configured kernel parameters and Oracle users

**See:** `modules/oracle-rac/README.md` for detailed infrastructure documentation  
**See:** `modules/oracle-rac/EXISTING-RESOURCES.md` for using existing VNet/subnets

## PoC vs Production Configuration

This module is **optimized for PoC environments** by default:

| Component | PoC Default | Production Option |
|-----------|-------------|-------------------|
| VM Size | Standard_D4s_v3 (4 vCPU, 16 GB) | Standard_D8s_v3+ (8 vCPU, 32 GB+) |
| OS Disk | 64 GB | 128 GB |
| Accelerated Networking | Disabled | Enabled |
| Monthly Cost | ~$310 | ~$640+ |

**To switch to production config**, adjust variables in your deployment:
```hcl
vm_size                      = "Standard_D8s_v3"
os_disk_size_gb              = 128
enable_accelerated_networking = true
```

## Architecture

### Network Topology

```
Confluent Cloud
    ↓
    Private Link Egress Endpoint
    ↓
Application Gateway (Existing)
    ↓
    ┌─────────────────────────────────────┐
    │  Oracle RAC Cluster (2 nodes)       │
    ├─────────────────────────────────────┤
    │                                     │
    │  ┌─────────┐      ┌─────────┐      │
    │  │ Node 1  │←────→│ Node 2  │      │
    │  │         │ IC   │         │      │
    │  │Instance1│      │Instance2│      │
    │  └────┬────┘      └────┬────┘      │
    │       │                │            │
    │       └────────┬───────┘            │
    │                ↓                    │
    │     ┌──────────────────────┐        │
    │     │  Azure Shared Disks  │        │
    │     │  (ASM Disk Groups)   │        │
    │     │  - OCR/Voting        │        │
    │     │  - DATA              │        │
    │     │  - FRA (backups)     │        │
    │     └──────────────────────┘        │
    └─────────────────────────────────────┘
```

### Integration with Application Gateway

The Oracle RAC cluster integrates with the existing Application Gateway setup:

1. **SCAN Listener** - Connects via Application Gateway backend pool
2. **Load Balancing** - AppGW distributes connections across SCAN listeners
3. **Health Probes** - AppGW monitors RAC node health
4. **Confluent Connector** - Connects to SCAN address through Private Link

## Deployment Guide

### Phase 1: Infrastructure (COMPLETE)

VMs and networking are already deployed. To deploy in your environment:

#### Option 1: Create New Subnets (Default)

```hcl
# In your main terraform configuration, enable Oracle RAC:
module "oracle_rac" {
  source = "./modules/oracle-rac/terraform"

  resource_prefix          = var.resource_prefix
  location                 = var.location
  resource_group_name      = local.resource_group_name
  vnet_name                = local.vnet_name
  vnet_resource_group_name = local.vnet_resource_group_name
  
  # Network configuration - create new subnets
  create_subnets                 = true
  rac_public_subnet_prefix       = "10.0.10.0/24"
  rac_private_subnet_prefix      = "10.0.11.0/24"
  rac_interconnect_subnet_prefix = "10.0.12.0/24"
  appgw_subnet_prefix            = var.appgw_subnet_prefix
  
  # Create NSGs for new subnets
  create_nsg = true
  
  # VM configuration (PoC defaults - adjust for production)
  vm_size                      = "Standard_D4s_v3"  # PoC: 4 vCPU, 16 GB RAM
  os_disk_size_gb              = 64  # PoC optimized
  enable_accelerated_networking = false  # Disabled for PoC cost savings
  
  # SSH configuration
  admin_username  = "azureuser"
  ssh_public_key  = var.oracle_ssh_public_key
  
  # Security
  admin_source_address_prefix = "YOUR_ADMIN_IP/32"
  create_public_ips           = false  # Use Bastion/VPN instead
  
  tags = var.tags
}
```

#### Option 2: Use Existing Subnets

If you already have subnets allocated in your VNet:

```hcl
module "oracle_rac" {
  source = "./modules/oracle-rac/terraform"

  resource_prefix          = var.resource_prefix
  location                 = var.location
  resource_group_name      = local.resource_group_name
  vnet_name                = local.vnet_name
  vnet_resource_group_name = local.vnet_resource_group_name
  
  # Network configuration - use existing subnets
  create_subnets = false
  existing_public_subnet_id       = "/subscriptions/.../subnets/rac-public"
  existing_private_subnet_id      = "/subscriptions/.../subnets/rac-private"
  existing_interconnect_subnet_id = "/subscriptions/.../subnets/rac-interconnect"
  appgw_subnet_prefix             = var.appgw_subnet_prefix
  
  # Skip NSG creation if subnets already have NSGs
  create_nsg = false
  
  # VM configuration (PoC defaults)
  vm_size                      = "Standard_D4s_v3"
  os_disk_size_gb              = 64
  enable_accelerated_networking = false
  
  # ... rest of config ...
}
```

**See:** `modules/oracle-rac/EXISTING-RESOURCES.md` for detailed existing VNet setup guide

Then deploy:
```bash
terraform apply
```

### Phase 2: Shared Storage (NEXT)

**Planned:** Azure Shared Disks for Oracle ASM

**Components to add:**
- 3x 10 GB Premium SSD (OCR and Voting disks)
- 3x 128 GB Premium SSD (DATA disk group)
- 3x 64 GB Premium SSD (FRA disk group for backups)

**Configuration:**
- Enable shared disk attachment to both RAC nodes
- Configure udev rules for persistent disk naming
- Set up disk permissions for grid user

**Status**: Ready to build when you approve Phase 1

### Phase 3: Grid Infrastructure Installation

**Steps:**
1. Download Oracle Grid Infrastructure 19c binaries
2. Upload to Azure (via SCP or Azure Files)
3. Configure /etc/hosts on both nodes with VIPs and SCAN
4. Set up SSH equivalence between nodes
5. Run Grid Infrastructure installer (gridSetup.sh)
6. Configure ASM disk groups (OCR, DATA, FRA)
7. Verify cluster services

**Status**: Awaiting Phase 2 completion

### Phase 4: Database Installation

**Steps:**
1. Download Oracle Database 19c binaries
2. Run Database Configuration Assistant (dbca)
3. Create RAC database with instances on both nodes
4. Configure SCAN listeners
5. Set up database services for failover
6. Configure archive log mode
7. Test failover scenarios

### Phase 5: XStream CDC Configuration

**Steps:**
1. Create XStream admin user (C##GGADMIN)
2. Grant necessary privileges for XStream
3. Configure XStream outbound server
4. Create sample schema and data (ORDERMGMT)
5. Test XStream connectivity from both nodes
6. Configure Confluent connector to use SCAN address

### Phase 6: Application Gateway Integration

**Steps:**
1. Add RAC SCAN addresses to Application Gateway backend pool
2. Update health probe to use SCAN listener (port 1521)
3. Update Oracle DNS record to point to SCAN
4. Test Confluent connector connectivity through AppGW
5. Configure failover behavior

## Prerequisites

### Oracle Software Licenses
- ✅ Oracle Database 19c Enterprise Edition license
- ✅ Oracle RAC license (or RAC One Node)
- ⚠️ Ensure compliance with Oracle licensing policies on Azure

### Downloads Required
- [ ] Oracle Grid Infrastructure 19.3+ for Linux x86-64
- [ ] Oracle Database 19.3+ Enterprise Edition for Linux x86-64
- [ ] Oracle Grid Infrastructure Patch Set Updates (PSUs) - latest recommended

**Download from:**
- Oracle Software Delivery Cloud: https://edelivery.oracle.com
- Oracle Support (for patches): https://support.oracle.com

### Tools Needed
- SSH client with X11 forwarding or VNC (for GUI installers)
- SCP/SFTP for file transfer
- Azure Bastion or Jump Host (if not using public IPs)

## Configuration for Confluent Connector

Once Oracle RAC is fully installed, update your Confluent XStream connector configuration:

```hcl
# confluent.tf
resource "confluent_connector" "oracle_xstream_rac" {
  # ... existing config ...

  config_nonsensitive = {
    "connector.class" = "OracleXStreamSource"
    "name"            = "oracle-rac-xstream-cdc"
    
    # Connect to SCAN address (not individual node IPs)
    # SCAN provides automatic load balancing and failover
    "database.hostname" = "oracle-scan.yourdomain.com"  # Or use SCAN IP
    "database.port"     = "1521"
    "database.service.name" = "RACDB_SERVICE"  # RAC service name
    
    # XStream configuration
    "database.user"           = "C##GGADMIN"
    "database.out.server.name" = "XOUT"
    
    # ... rest of config ...
  }
}
```

**Benefits of RAC for Confluent:**
- **High Availability**: If one RAC node fails, connector automatically fails over to remaining node
- **Load Distribution**: SCAN distributes connections across healthy nodes
- **Zero Downtime Maintenance**: Patch one node while connector uses the other
- **Better Performance**: Can scale reads across multiple instances

## IP Address Allocation

Current allocation for 2-node RAC cluster:

| Node/Component | Public Subnet | Private Subnet | Interconnect Subnet |
|----------------|---------------|----------------|---------------------|
| Node 1         | 10.0.10.10    | 10.0.11.10     | 10.0.12.10          |
| Node 2         | 10.0.10.11    | 10.0.11.11     | 10.0.12.11          |
| Node 1 VIP     | 10.0.10.30    | -              | -                   |
| Node 2 VIP     | 10.0.10.31    | -              | -                   |
| SCAN VIP 1     | 10.0.10.20    | -              | -                   |
| SCAN VIP 2     | 10.0.10.21    | -              | -                   |
| SCAN VIP 3     | 10.0.10.22    | -              | -                   |

**Application Gateway Backend Pool**: Use SCAN VIPs (10.0.10.20-22)

## Cost Estimate

### PoC Configuration (Default)

| Component | Specification | Monthly Cost |
|-----------|---------------|--------------|
| 2x VMs | Standard_D4s_v3 (4 vCPU, 16 GB) | ~$290 |
| OS Disks | 2x 64 GB Premium SSD | ~$20 |
| Shared Disks (ASM) | Phase 2: ~6-9 disks | ~$200 |
| **Phase 1-2 Total** | PoC infrastructure | **~$510/month** |

### Production Configuration (Optional)

| Component | Specification | Monthly Cost |
|-----------|---------------|--------------|
| 2x VMs | Standard_D8s_v3 (8 vCPU, 32 GB) | ~$600 |
| OS Disks | 2x 128 GB Premium SSD | ~$40 |
| Shared Disks (ASM) | 9x disks (OCR+DATA+FRA) | ~$300 |
| **Phase 1-2 Total** | Production infrastructure | **~$940/month** |

**Plus existing costs:**
- Application Gateway: ~$90-110/month (shared)
- Private Link: Minimal
- Confluent Cloud: Based on connector usage

**Compared to standalone Oracle:**
- Standalone (XE): ~$150/month (PoC VM + disks)
- RAC (PoC): ~$510/month (2 smaller VMs + shared disks)
- RAC (Production): ~$940/month (2 VMs + shared disks)
- **Premium for HA (PoC)**: ~$360/month (~3.4x cost)
- **Premium for HA (Prod)**: ~$640/month (~6x cost vs standalone PoC)

## Compatibility with Existing Setup

The Oracle RAC module is designed to integrate seamlessly with your existing setup:

✅ **Works with existing AppGW** - Just add RAC SCAN to backend pool  
✅ **Uses existing VNet** - Adds 3 new subnets for RAC  
✅ **Uses existing Private Link** - Same egress endpoint  
✅ **Independent from standalone Oracle** - Can run both simultaneously  
✅ **Same XStream connector** - Just change hostname to SCAN address  

## Migration Path from Standalone to RAC

If you want to migrate from the existing standalone Oracle setup to RAC:

1. **Parallel deployment** - Deploy RAC alongside existing standalone Oracle
2. **Data migration** - Use Data Guard or Data Pump to migrate data
3. **Test XStream** - Validate XStream CDC works on RAC with test data
4. **Update connector** - Switch connector to SCAN address
5. **Decommission standalone** - Remove standalone Oracle VM after validation

**Zero downtime migration is possible** using Oracle Data Guard for continuous replication.

## Current Status Summary

✅ **Phase 1: Infrastructure** - COMPLETE  
⏳ **Phase 2: Shared Storage** - READY TO BUILD  
⏳ **Phase 3: Grid Infrastructure** - AWAITING PHASE 2  
⏳ **Phase 4: Database** - AWAITING PHASE 3  
⏳ **Phase 5: XStream CDC** - AWAITING PHASE 4  
⏳ **Phase 6: AppGW Integration** - AWAITING PHASE 5  

## Next Steps

**Review Phase 1** and confirm you're ready to proceed:

1. **Access the VMs** - SSH to both nodes and verify basic connectivity
2. **Review network topology** - Ensure subnet allocations fit your environment
3. **Confirm VM sizing** - Standard_D8s_v3 suitable or need larger?
4. **Plan storage** - How much space needed for your database?

When ready for Phase 2, I'll create:
- `modules/oracle-rac/terraform/storage.tf` - Azure Shared Disks configuration
- Installation scripts for Grid Infrastructure
- Detailed installation guide

## Troubleshooting & Support

**Common issues during Phase 1:**
- Marketplace image terms not accepted → Run `az vm image terms accept`
- Cannot SSH to VMs → Check NSG rules and admin_source_address_prefix
- Accelerated networking errors → Verify VM size supports it

**See:** `modules/oracle-rac/README.md` for detailed troubleshooting

## References

- [Oracle RAC on Azure Documentation](https://docs.oracle.com/en/database/oracle/oracle-database/19/racad/)
- [Azure Shared Disks for Oracle](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-shared)
- [Oracle Grid Infrastructure Installation](https://docs.oracle.com/en/database/oracle/oracle-database/19/cwlin/)
- [Oracle XStream on RAC](https://docs.oracle.com/en/database/oracle/oracle-database/19/xstrm/)
