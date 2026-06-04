# Oracle RAC Deployment Options: Cloud Provider Comparison

**Date:** 2026-05-20  
**Purpose:** Evaluate Oracle RAC deployment options across AWS, GCP, and OCI for Confluent XStream CDC connector testing

---

## Executive Summary

After 14 hours of failed attempts to deploy Oracle RAC on Azure, this document evaluates alternative cloud providers for Oracle RAC deployment. Each provider offers both **managed services** and **self-install** options.

### Quick Recommendation Matrix

| Provider | Managed RAC | Self-Install RAC | Difficulty | Time to Deploy | Official Support |
|----------|-------------|------------------|------------|----------------|------------------|
| **OCI** | ✅ Yes (Multiple) | ✅ Yes | ⭐ Easy | 1-2 hours | ✅ Full |
| **AWS** | ⚠️ RAC One Node | ✅ Yes (Bare Metal) | ⭐⭐ Medium | 3-4 hours | ✅ Full |
| **GCP** | ✅ Yes (Bare Metal) | ✅ Yes | ⭐⭐⭐ Hard | 4-6 hours | ⚠️ Limited |
| **Azure** | ❌ No | ❌ Not viable | ⭐⭐⭐⭐⭐ Impossible | N/A | ❌ Not supported |

---

## Oracle Cloud Infrastructure (OCI) - RECOMMENDED ⭐

### Overview
OCI is Oracle's native cloud platform and provides the **best support for Oracle RAC** across all deployment options.

### Managed Options

#### 1. **Exadata Cloud Service (ExaCS)** - BEST FOR PRODUCTION
- **What:** Oracle's premium managed database service on Exadata infrastructure
- **RAC Support:** Full multi-node RAC (2+ nodes)
- **Configuration:** Fully managed, automatic provisioning
- **Pros:**
  - Highest performance (Exadata hardware)
  - Fully managed patching, backups, HA
  - Production-grade for enterprise workloads
  - Complete RAC feature set
  - Official Oracle support
- **Cons:**
  - Most expensive option ($$$$$)
  - Minimum commitment requirements
  - Overkill for testing/development
- **Deployment Time:** 1-2 hours (automated)
- **Best For:** Production XStream CDC deployments

#### 2. **Base Database Service with RAC** - BEST FOR TESTING ⭐ RECOMMENDED
- **What:** Managed Oracle Database on VM infrastructure with RAC option
- **RAC Support:** 2-node RAC cluster
- **Configuration:** Select "2 Node RAC" during provisioning
- **Pros:**
  - Much lower cost than Exadata ($$)
  - Fully managed (patching, backups, monitoring)
  - True multi-node RAC
  - Perfect for testing XStream CDC
  - Official Oracle support
  - Simple provisioning through OCI Console
- **Cons:**
  - Limited to 2 nodes (sufficient for testing)
  - VM-based performance (not Exadata)
- **Deployment Time:** 1-2 hours (automated)
- **Requirements:**
  - OCI tenancy with appropriate quotas
  - VCN (Virtual Cloud Network) with subnet
  - SSH key pair
  - Choose DB version (19c recommended for XStream)
- **Estimated Cost:** ~$500-1500/month depending on VM size
- **Best For:** XStream CDC connector testing (RECOMMENDED)

#### 3. **Autonomous Database Shared**
- **What:** Oracle's serverless managed database
- **RAC Support:** Infrastructure uses RAC but not exposed to users
- **Note:** Not suitable for RAC-specific testing as RAC layer is abstracted

### Self-Install Options on OCI

#### 4. **VM Database System (Manual RAC Install)**
- **What:** Provision VMs and install Grid Infrastructure + RAC yourself
- **RAC Support:** Full multi-node RAC (2+ nodes)
- **Configuration:** Manual installation similar to on-premises
- **Pros:**
  - Full control over RAC configuration
  - Lower cost than managed services ($)
  - Can customize cluster topology
  - Native OCI networking (no multicast issues like Azure)
- **Cons:**
  - Requires Oracle RAC expertise
  - Manual installation and maintenance
  - 6-8 hours installation time
  - You manage patching, backups, HA
- **Deployment Time:** 6-8 hours (manual)
- **Requirements:**
  - Oracle Grid Infrastructure 19c installer
  - Oracle Database 19c installer
  - 2+ Oracle Linux VMs (Standard or HPC shapes)
  - Shared block storage for ASM (iSCSI or NFS)
  - Private interconnect network
- **Best For:** Learning RAC internals, custom configurations

---

## Amazon Web Services (AWS)

### Managed Options

#### 1. **Amazon RDS for Oracle with RAC One Node**
- **What:** Managed Oracle Database service
- **RAC Support:** ⚠️ **RAC One Node** only (NOT true multi-node RAC)
- **What is RAC One Node:**
  - Single-instance database on a 2-node cluster
  - Provides fast failover but NOT active-active
  - Uses RAC technology but only one instance runs at a time
  - **NOT suitable for testing true multi-node RAC with XStream**
- **Pros:**
  - Fully managed (patching, backups, HA)
  - Simple provisioning
  - Automatic failover
  - Official AWS/Oracle support
- **Cons:**
  - ⚠️ **NOT true multi-node RAC** (only 1 active instance)
  - Cannot test RAC-specific features like parallel DML
  - Limited Oracle version support
  - RDS restrictions on advanced features
- **Deployment Time:** 30-60 minutes (automated)
- **Best For:** High availability, but NOT for RAC-specific testing
- **Verdict:** ❌ **NOT SUITABLE** for your RAC testing requirements

### Self-Install Options on AWS

#### 2. **EC2 Bare Metal Instances with Manual RAC Install** - VIABLE OPTION
- **What:** Bare metal EC2 instances (i3.metal, i4i.metal) with manual RAC installation
- **RAC Support:** Full multi-node RAC (2+ nodes)
- **Configuration:** Install Grid Infrastructure + RAC manually
- **Pros:**
  - True bare metal performance
  - Full control over RAC configuration
  - Access to all RAC features
  - Can use local NVMe storage for ASM
  - Supported by both AWS and Oracle
- **Cons:**
  - Expensive bare metal instances ($$$)
  - Manual installation required (6-8 hours)
  - Complex networking setup (Elastic Fabric Adapter for interconnect)
  - You manage all patching, backups, HA
  - Requires deep RAC expertise
- **Deployment Time:** 8-12 hours (manual)
- **Requirements:**
  - 2+ EC2 bare metal instances (i3.metal, i4i.metal, or x2iedn.metal)
  - Oracle Grid Infrastructure 19c installer
  - Oracle Database 19c installer
  - VPC with multiple subnets (public, private, interconnect)
  - Elastic Network Interfaces (ENI) for cluster networking
  - Elastic Fabric Adapter (EFA) for low-latency interconnect
  - EBS volumes or local NVMe for shared storage
  - Careful network configuration (no multicast, use unicast)
- **Network Challenge:** AWS VPC doesn't support multicast (like Azure)
  - Solution: Configure Grid Infrastructure to use unicast instead
  - Easier than Azure because Oracle provides unicast configuration
- **Estimated Cost:** ~$6000-12000/month (bare metal is expensive)
- **Best For:** Production RAC on AWS, specific AWS integration requirements

#### 3. **EC2 Standard Instances (c5, m5, r5) with Manual RAC Install**
- **What:** Standard EC2 VMs with manual RAC installation
- **RAC Support:** Technically possible but **NOT RECOMMENDED**
- **Issues:**
  - Performance limitations (virtualized)
  - Complex shared storage setup (iSCSI over network)
  - Network latency for interconnect
  - Oracle may not certify/support this configuration
- **Verdict:** ❌ **NOT RECOMMENDED** - use bare metal or managed option

---

## Google Cloud Platform (GCP)

### Managed Options

#### 1. **Bare Metal Solution for Oracle**
- **What:** Dedicated bare metal servers managed by Google with Oracle pre-installed
- **RAC Support:** Full multi-node RAC (2+ nodes)
- **Configuration:** Managed infrastructure, Oracle software pre-configured
- **Pros:**
  - Dedicated bare metal hardware
  - Oracle Solaris or Linux support
  - Managed hardware, networking, and storage
  - Suitable for Oracle workloads
  - High-speed interconnect (RoCE)
- **Cons:**
  - Very expensive ($$$$$)
  - Limited availability (select regions only)
  - Minimum commitment (typically 36 months)
  - Longer provisioning time (days to weeks)
  - Overkill for testing
- **Deployment Time:** 3-7 days (requires provisioning physical hardware)
- **Estimated Cost:** ~$10,000-30,000/month (hardware commitment)
- **Best For:** Large-scale production Oracle deployments on GCP
- **Verdict:** ⚠️ Too expensive and slow for testing

### Self-Install Options on GCP

#### 2. **Compute Engine VMs with Manual RAC Install**
- **What:** GCP VMs with manual Oracle RAC installation
- **RAC Support:** Full multi-node RAC (2+ nodes)
- **Configuration:** Manual Grid Infrastructure + RAC installation
- **Pros:**
  - Flexible VM sizing
  - Lower cost than bare metal ($$)
  - Full control over configuration
- **Cons:**
  - Manual installation (6-8 hours)
  - Limited Oracle support/certification for GCP
  - Complex networking (GCP doesn't support multicast)
  - Need to configure unicast clustering
  - Requires persistent disk for shared storage (performance concerns)
  - You manage everything
- **Deployment Time:** 8-12 hours (manual)
- **Requirements:**
  - 2+ Compute Engine VMs (n2-highmem or c2 series)
  - Oracle Grid Infrastructure 19c installer
  - Oracle Database 19c installer
  - VPC with multiple subnets
  - Persistent disks for shared storage (ASM)
  - Multiple network interfaces per VM
  - Unicast cluster configuration
- **Network Challenge:** GCP VPC doesn't support multicast
  - Solution: Configure Grid Infrastructure for unicast
  - Documented but less common than OCI
- **Estimated Cost:** ~$800-2000/month depending on VM size
- **Best For:** Testing when GCP is organizational standard
- **Verdict:** ⚠️ **POSSIBLE but NOT RECOMMENDED** - limited support

---

## Detailed Comparison

### Cost Comparison (Monthly Estimates for 2-Node RAC)

| Option | Infrastructure | Storage | Total/Month | Notes |
|--------|---------------|---------|-------------|-------|
| **OCI Base DB Service with RAC** | $400-1000 | $100-300 | **$500-1300** | BEST VALUE ⭐ |
| OCI Exadata Cloud Service | $3000-8000 | Included | $3000-8000 | Production grade |
| OCI VM Self-Install | $200-600 | $50-200 | $250-800 | Cheapest but manual |
| AWS RDS Oracle (RAC One Node) | $500-1500 | Included | $500-1500 | NOT true RAC ❌ |
| AWS EC2 Bare Metal Self-Install | $5000-10000 | $200-500 | $5200-10500 | Very expensive |
| GCP Bare Metal Solution | $10000-25000 | Included | $10000-25000 | Enterprise only |
| GCP Compute Engine Self-Install | $400-1200 | $100-300 | $500-1500 | Limited support |
| Azure (any option) | N/A | N/A | **NOT VIABLE** | ❌ |

### Feature Comparison

| Feature | OCI Base DB RAC | OCI Self-Install | AWS RDS RAC One | AWS EC2 Bare Metal | GCP Bare Metal | GCP Self-Install |
|---------|----------------|------------------|-----------------|-------------------|----------------|------------------|
| **Multi-node RAC** | ✅ Yes (2 nodes) | ✅ Yes (2+) | ❌ No (1 active) | ✅ Yes (2+) | ✅ Yes (2+) | ✅ Yes (2+) |
| **XStream CDC** | ✅ Yes | ✅ Yes | ⚠️ Limited | ✅ Yes | ✅ Yes | ✅ Yes |
| **Managed Patching** | ✅ Yes | ❌ No | ✅ Yes | ❌ No | ⚠️ Partial | ❌ No |
| **Managed Backups** | ✅ Yes | ❌ No | ✅ Yes | ❌ No | ⚠️ Partial | ❌ No |
| **Oracle Support** | ✅ Full | ✅ Full | ✅ Full | ✅ Full | ⚠️ Limited | ⚠️ Minimal |
| **Time to Deploy** | 1-2 hours | 6-8 hours | 1 hour | 8-12 hours | 3-7 days | 8-12 hours |
| **Cluster Admin Access** | ⚠️ Limited | ✅ Full | ❌ No | ✅ Full | ✅ Full | ✅ Full |
| **ASM Control** | ⚠️ Managed | ✅ Full | ❌ No | ✅ Full | ✅ Full | ✅ Full |

### Network Requirements Comparison

| Provider | Multicast Support | Interconnect Solution | Shared Storage | Complexity |
|----------|------------------|----------------------|----------------|------------|
| **OCI** | ✅ Yes (native) | Native RoCE/RDMA | Block volumes, NFS | ⭐ Easy |
| **AWS** | ❌ No | EFA (Elastic Fabric Adapter) | EBS, local NVMe | ⭐⭐⭐ Medium |
| **GCP** | ❌ No | Unicast config required | Persistent disks | ⭐⭐⭐⭐ Hard |
| **Azure** | ❌ No | VXLAN workaround required | Shared disks | ⭐⭐⭐⭐⭐ Impossible |

---

## Recommendations

### For XStream CDC Connector Testing (Your Use Case)

**Primary Recommendation: OCI Base Database Service with RAC** ⭐⭐⭐⭐⭐

**Why:**
1. ✅ **True 2-node RAC** - Tests actual multi-instance RAC behavior
2. ✅ **Fully managed** - Minimal operational overhead
3. ✅ **Fast deployment** - 1-2 hours vs 6-8+ hours for self-install
4. ✅ **Best cost-value** - $500-1300/month for testing
5. ✅ **Official Oracle support** - Direct support from Oracle
6. ✅ **XStream CDC ready** - All features available
7. ✅ **No network workarounds** - Native Oracle networking
8. ✅ **Proven platform** - OCI is Oracle's native cloud

**Deployment Steps:**
1. Create OCI account (free tier available for testing)
2. Set up VCN (Virtual Cloud Network) and subnet
3. Provision Base Database Service
   - Select "2 Node RAC" cluster type
   - Choose Oracle Database 19c
   - Select VM shape (VM.Standard2.4 or higher)
   - Configure storage (500GB+ for DATA, 200GB+ for RECO)
4. Configure XStream CDC
5. Test Confluent connector

**Estimated Total Time:** 2-3 hours (mostly automated)

---

### Alternative Recommendation: AWS EC2 Bare Metal (If AWS is Required)

**When to Choose:**
- Organizational requirement to use AWS
- Existing AWS infrastructure/integration
- Willing to invest time in manual setup
- Budget for bare metal instances

**Deployment Steps:**
1. Provision 2x EC2 bare metal instances (i3.metal recommended)
2. Configure VPC with 3 subnets (public, private, interconnect)
3. Attach Elastic Fabric Adapters (EFA) for cluster interconnect
4. Configure storage (local NVMe or EBS)
5. Install Oracle Linux 7 or 8
6. Configure Grid Infrastructure for unicast (not multicast)
7. Install Oracle Grid Infrastructure 19c
8. Create ASM disk groups
9. Install Oracle Database 19c RAC
10. Configure XStream CDC

**Estimated Total Time:** 10-14 hours (manual setup + troubleshooting)
**Estimated Cost:** $5000-10000/month

---

### NOT Recommended

❌ **AWS RDS for Oracle with RAC One Node**
- Reason: Not true multi-node RAC, cannot test RAC-specific features

❌ **GCP Bare Metal Solution**
- Reason: Too expensive ($10k-30k/month), long provisioning time, overkill for testing

❌ **GCP Compute Engine Self-Install**
- Reason: Limited Oracle support, complex networking, better alternatives exist

❌ **Azure (any option)**
- Reason: 14 hours of attempts proved it's not viable for Oracle RAC 19c

---

## Quick Start Guide: OCI Base Database Service with RAC

### Prerequisites
1. OCI account (can use 30-day free trial with $300 credit)
2. SSH key pair for VM access
3. Oracle Database 19c license or use included license

### Step-by-Step Deployment

1. **Create VCN** (if not exists)
   ```
   OCI Console → Networking → Virtual Cloud Networks → Create VCN
   - Name: oracle-rac-vcn
   - CIDR: 10.0.0.0/16
   - Create public subnet: 10.0.1.0/24
   ```

2. **Provision RAC Database**
   ```
   OCI Console → Oracle Database → Bare Metal, VM, and Exadata → Create DB System
   
   Configure DB system:
   - Name: oracle-rac-test
   - Availability domain: Choose one
   - Shape: VM.Standard2.4 (or higher for performance)
   - Total node count: 2 ← IMPORTANT
   - Oracle Database software edition: Enterprise Edition Extreme Performance
   - Available storage: 256 GB
   - License type: Bring Your Own License (or License Included)
   
   Configure database:
   - Database name: RACDB
   - Database version: 19c
   - PDB name: PDB1
   - Admin password: <strong password>
   
   Configure networking:
   - VCN: oracle-rac-vcn
   - Client subnet: public subnet
   - Hostname prefix: racnode
   - Scan DNS name: racscan
   
   SSH keys:
   - Upload your public SSH key
   
   → Create DB System
   ```

3. **Wait for Provisioning** (60-120 minutes)
   - Status will change from "Provisioning" to "Available"
   - Both nodes will be configured automatically
   - RAC cluster will be running

4. **Verify RAC Cluster**
   ```bash
   # SSH to node 1
   ssh -i <private-key> opc@<node1-public-ip>
   
   # Check cluster status
   sudo su - grid
   crsctl status resource -t
   
   # Check database instances
   srvctl status database -d RACDB
   # Should show: Instance RACDB1 is running on node racnode1
   #              Instance RACDB2 is running on node racnode2
   ```

5. **Configure XStream CDC**
   ```sql
   -- Connect to database
   sqlplus sys/<password>@<scan-name>:1521/RACDB as sysdba
   
   -- Enable archive log mode (if not already)
   shutdown immediate;
   startup mount;
   alter database archivelog;
   alter database open;
   
   -- Create XStream administrator
   CREATE TABLESPACE xstream_adm_tbs DATAFILE SIZE 25M AUTOEXTEND ON MAXSIZE UNLIMITED;
   CREATE USER xstrmadmin IDENTIFIED BY <password>
     DEFAULT TABLESPACE xstream_adm_tbs
     QUOTA UNLIMITED ON xstream_adm_tbs;
   
   GRANT CREATE SESSION TO xstrmadmin;
   
   BEGIN
     DBMS_XSTREAM_AUTH.GRANT_ADMIN_PRIVILEGE(
       grantee => 'xstrmadmin',
       privilege_type => 'CAPTURE',
       grant_select_privileges => TRUE
     );
   END;
   /
   
   -- Create outbound server
   BEGIN
     DBMS_XSTREAM_ADM.CREATE_OUTBOUND(
       server_name => 'CONFLUENT_OUT',
       table_names => 'SCHEMA.TABLE_NAME',
       source_database => 'RACDB'
     );
   END;
   /
   
   -- Start outbound server
   BEGIN
     DBMS_XSTREAM_ADM.START_OUTBOUND(server_name => 'CONFLUENT_OUT');
   END;
   /
   ```

6. **Test Confluent Connector**
   - Configure Confluent Oracle CDC Source Connector
   - Point to RAC SCAN address: `<scan-name>:1521/RACDB`
   - Use xstrmadmin credentials
   - Test data replication from both RAC instances

### Total Cost Estimate (OCI Base DB Service with RAC)
```
VM.Standard2.4 shape × 2 nodes:          ~$350/month
Storage (500GB DATA + 200GB RECO):       ~$75/month
Backup storage (optional):                ~$25/month
Network egress (minimal for testing):     ~$10/month
----------------------------------------------------------
Total:                                   ~$460/month

With license included:                   ~$800-1000/month
```

### Cleanup After Testing
```
OCI Console → Oracle Database → DB Systems → <your-db-system> → Terminate
```
All resources (VMs, storage, networking) are deleted automatically.

---

## Conclusion

**For Confluent XStream CDC connector testing against Oracle RAC:**

1. **BEST OPTION:** Oracle Cloud Infrastructure Base Database Service with 2-Node RAC
   - Fast, affordable, fully managed, officially supported
   - Estimated cost: $500-1300/month
   - Deployment time: 1-2 hours

2. **IF AWS IS REQUIRED:** EC2 Bare Metal with self-installed RAC
   - More complex, expensive, time-consuming
   - Estimated cost: $5000-10000/month
   - Deployment time: 10-14 hours

3. **AVOID:** Azure, GCP, AWS RDS (RAC One Node)
   - Azure: Not viable (proven through 14 hours of attempts)
   - GCP: Limited support, high complexity
   - AWS RDS: Not true multi-node RAC

**Recommended Next Step:**
Start with OCI Base Database Service with RAC for testing. If successful and production deployment is needed, evaluate Exadata Cloud Service or AWS bare metal based on organizational requirements.

---

## Additional Resources

### OCI Documentation
- [Oracle Base Database Service Documentation](https://docs.oracle.com/en-us/iaas/Content/Database/Concepts/overview.htm)
- [Creating a DB System with RAC](https://docs.oracle.com/en-us/iaas/Content/Database/Tasks/creatingDBsystem.htm)
- [Oracle RAC on OCI Best Practices](https://docs.oracle.com/en/solutions/deploy-oracle-db-rac-oci/)

### AWS Documentation
- [Oracle on AWS Best Practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/oracle-database.html)
- [Amazon RDS for Oracle](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Oracle.html)
- [Oracle RAC on EC2 (Self-Managed)](https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/deploy-oracle-rac-on-amazon-ec2.html)

### GCP Documentation
- [Bare Metal Solution for Oracle](https://cloud.google.com/bare-metal/docs)
- [Oracle Database on GCP](https://cloud.google.com/solutions/oracle)

### Oracle XStream Documentation
- [Oracle XStream Guide 19c](https://docs.oracle.com/en/database/oracle/oracle-database/19/xstrm/)
- [Confluent Oracle CDC Source Connector](https://docs.confluent.io/kafka-connectors/oracle-cdc/current/overview.html)

---

**Document Version:** 1.0  
**Last Updated:** 2026-05-20  
**Author:** Claude Code with Peter Gustafsson
