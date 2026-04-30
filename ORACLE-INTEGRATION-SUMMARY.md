# Oracle XStream CDC Integration - Summary

## 🎉 What's New

This repository now supports **Oracle XStream CDC** as a second connector option alongside IBM MQ, sharing the same Azure Application Gateway infrastructure for cost-effective multi-connector deployments.

## Architecture

```
Confluent Cloud
  ↓ (Egress Private Link)
Azure Application Gateway (Single Instance)
  ├─ Port 1414 → IBM MQ Backend
  └─ Port 1521 → Oracle Database Backend
       ↓
    [Optional] Oracle XE 21c (Auto-provisioned)
       ├─ Docker Container on Azure VM
       ├─ XStream Outbound Server
       └─ Sample Schema (ORDERMGMT)
```

## What Was Added

### 1. Oracle Database Provisioning Module
**Location:** `modules/oracle-database/`

**Terraform Module** (`terraform/`):
- `main.tf` - Azure VM with Oracle XE 21c in Docker
- `variables.tf` - Configuration options
- `outputs.tf` - Oracle connection details

**Setup Scripts** (`scripts/`):
- `cloud-init.yaml` - Automated Docker + Oracle installation
- `00_setup_cdc.sh` - Master setup script
- `01_setup_database.sql` - Archive log, redo logs, supplemental logging
- `02_create_user.sql` - Application user (ordermgmt)
- `03_create_schema_datamodel.sql` - Tables (ORDERS, CUSTOMERS, PRODUCTS, etc.)
- `04_load_data.sql` - Initial sample data
- `05_21c_create_user.sql` - XStream users (C##GGADMIN, C##CFLTUSER)
- `05_21c_privs.sql` - XStream privileges
- `06_data_generator.sql` - Procedures to generate test data

**Features:**
- ✅ Fully automated Oracle provisioning
- ✅ XStream CDC pre-configured
- ✅ Sample data for immediate testing
- ✅ NSG rules for App Gateway connectivity
- ✅ Optional public IP for SSH access

### 2. Oracle Connector Configuration
**Location:** `connectors/oracle-xstream/`

- `README.md` - Connector setup guide
- `oracle-xstream.env.example` - Configuration template

**Connector Capabilities:**
- Captures INSERT, UPDATE, DELETE in real-time
- Initial snapshot of existing data
- Schema evolution support
- Works with Oracle 19c, 21c XE (Standalone databases only, RAC not supported)

### 3. Application Gateway Updates
**Location:** `main.tf`

**Added Oracle Backend (Dynamic Configuration):**
- Frontend port 1521 (Oracle)
- Backend address pool for Oracle servers
- TCP health probe for Oracle
- TCP backend settings
- TCP listener
- TCP routing rule (priority 200)

All Oracle components are **conditionally created** based on `oracle_backend_targets` variable.

### 4. Variables
**Location:** `variables.tf`

**Oracle Backend:**
- `oracle_backend_targets` - List of Oracle IPs/FQDNs
- `oracle_backend_port` - Default: 1521
- `oracle_frontend_port` - Default: 1521

**Oracle Provisioning:**
- `provision_oracle_database` - Enable automatic provisioning
- `oracle_vm_size` - VM size (default: Standard_D4s_v3)
- `oracle_ssh_public_key` - SSH public key
- `oracle_ssh_private_key_path` - SSH private key path
- `oracle_sys_password` - Oracle SYS password
- `oracle_pdb_name` - PDB name (default: XEPDB1)

**Oracle Connector:**
- `create_oracle_connector` - Deploy connector
- `oracle_connector_name` - Connector name
- `oracle_db_user` - XStream user (default: C##GGADMIN)
- `oracle_db_password` - XStream password
- `oracle_db_hostname` - Oracle hostname
- `oracle_table_include_list` - Tables to capture (regex)
- `oracle_topic_prefix` - Kafka topic prefix
- `oracle_snapshot_mode` - Snapshot mode (initial, schema_only, never)

### 5. Documentation
- `ORACLE-XSTREAM-SETUP.md` - Complete setup guide
- `modules/oracle-database/README.md` - Module documentation
- `connectors/oracle-xstream/README.md` - Connector guide

## How to Use

### Quick Start (PoC with Auto-Provisioned Oracle)

**1. Configure `terraform.tfvars`:**

```hcl
# Enable Oracle provisioning
provision_oracle_database = true
oracle_ssh_public_key     = file("~/.ssh/id_rsa.pub")

# Oracle will be automatically added as backend
# (oracle_backend_targets populated from module output)

# Deploy Oracle connector
create_oracle_connector = true
oracle_db_password      = "Confluent12!"

# Tables to capture
oracle_table_include_list = "ORDERMGMT[.](ORDERS|CUSTOMERS|PRODUCTS)"

# Kafka configuration
kafka_cluster_id = "lkc-xxxxx"
kafka_api_key    = "your-key"
kafka_api_secret = "your-secret"
```

**2. Deploy:**

```bash
terraform init
terraform plan
terraform apply
```

**3. Create XStream Outbound Server:**

```bash
# SSH to Oracle VM
ssh oracleadmin@$(terraform output -raw oracle_public_ip)

# Create outbound server
docker exec -it oracle21c sqlplus C##GGADMIN/Confluent12!@XE

BEGIN
  DBMS_XSTREAM_ADM.CREATE_OUTBOUND(
    server_name     => 'XOUT',
    table_names     => 'ORDERMGMT.ORDERS,ORDERMGMT.CUSTOMERS,ORDERMGMT.PRODUCTS',
    source_database => 'XEPDB1'
  );
END;
/
```

**4. Verify:**

```bash
# Check connector status
terraform output oracle_connector_status

# View captured data
kafka-console-consumer --bootstrap-server <bootstrap> \
  --topic oracle.ORDERMGMT.ORDERS \
  --from-beginning
```

### Use Existing Oracle Database

```hcl
# terraform.tfvars
provision_oracle_database = false
oracle_backend_targets    = ["10.0.5.10"]  # Your Oracle IP

create_oracle_connector = true
oracle_db_hostname      = "10.0.5.10"
oracle_db_name          = "ORCLCDB"
oracle_pdb_name         = "ORCLPDB1"
oracle_out_server_name  = "XOUT"
```

## Multi-Connector Deployment

### Both IBM MQ and Oracle

```hcl
# terraform.tfvars

# IBM MQ Backend
ibm_mq_backend_targets = ["10.0.2.10"]
create_connector       = true  # IBM MQ connector

# Oracle Backend
provision_oracle_database = true  # Or use existing
create_oracle_connector   = true

# Both connectors share the same:
# - Application Gateway
# - Private Link endpoint
# - Confluent Cloud network
# - Azure infrastructure
```

**Cost Savings:**
- Single App Gateway: ~$100/month (shared)
- vs. Two App Gateways: ~$200/month
- **Saves ~$100/month**

## File Structure

```
.
├── main.tf                           # Updated: Oracle backend added
├── variables.tf                      # Updated: Oracle variables added
├── confluent.tf                      # Ready for Oracle connector
├── modules/
│   └── oracle-database/              # NEW
│       ├── README.md
│       ├── terraform/
│       │   ├── main.tf              # Azure VM + Oracle provisioning
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── scripts/
│           ├── cloud-init.yaml      # Docker + Oracle installation
│           ├── 00_setup_cdc.sh      # Master setup script
│           ├── 01_setup_database.sql
│           ├── 02_create_user.sql
│           ├── 03_create_schema_datamodel.sql
│           ├── 04_load_data.sql
│           ├── 05_21c_create_user.sql
│           ├── 05_21c_privs.sql
│           └── 06_data_generator.sql
├── connectors/
│   ├── ibm-mq/                       # Existing
│   └── oracle-xstream/               # NEW
│       ├── README.md
│       └── oracle-xstream.env.example
├── ORACLE-XSTREAM-SETUP.md           # NEW - Complete guide
└── ORACLE-INTEGRATION-SUMMARY.md     # NEW - This file
```

## Benefits

### ✅ Complete Oracle XStream CDC Solution
- No manual Oracle installation required
- XStream pre-configured
- Sample data included for immediate testing

### ✅ Infrastructure as Code
- 100% Terraform-managed
- Reproducible deployments
- Version controlled configuration

### ✅ Cost Optimized
- Shared Application Gateway infrastructure
- Oracle XE (free edition) for PoCs
- Optional: Auto-shutdown when not in use

### ✅ Production Ready
- Network isolation via Private Link
- NSG-based access control
- Optional: Remove public IPs for production
- Supports Enterprise Edition for production workloads

## What's NOT Included

- ❌ **Oracle XStream Outbound Server creation** - Must be done manually (see guide)
  - Reason: Server config is specific to tables/schema requirements
  - Takes 2 minutes via SQL

- ❌ **Automatic Confluent connector deployment via Terraform**
  - Can be added to `confluent.tf` (template ready)
  - Or deploy via Confluent CLI/UI

- ❌ **Oracle Enterprise Edition licensing**
  - This setup uses Oracle XE (free)
  - For production with EE, ensure proper licensing

## Testing

### Verify Oracle Setup

```bash
# Check Oracle is running
ssh oracleadmin@<oracle-ip>
docker ps
docker logs oracle21c

# Check sample data
docker exec -it oracle21c sqlplus ordermgmt/kafka@XEPDB1
SQL> SELECT COUNT(*) FROM orders;
```

### Generate Test Data

```sql
-- Connect to PDB
docker exec -it oracle21c sqlplus ordermgmt/kafka@XEPDB1

-- Generate orders
EXEC generate_orders(100);
COMMIT;

-- Verify in Kafka topics
```

### Monitor Capture

```sql
-- Check XStream capture progress
docker exec -it oracle21c sqlplus C##GGADMIN/Confluent12!@XE

SELECT server_name, captured_scn, applied_scn, status
FROM DBA_XSTREAM_OUTBOUND_PROGRESS;
```

## Next Steps

1. **Review Documentation:**
   - Read `ORACLE-XSTREAM-SETUP.md` for detailed setup
   - Check `modules/oracle-database/README.md` for module details

2. **Deploy:**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. **Create XStream Server:**
   - Follow post-deployment steps in `ORACLE-XSTREAM-SETUP.md`

4. **Monitor:**
   - Check connector status
   - View captured data in Kafka
   - Monitor Oracle XStream server

## Troubleshooting

See `ORACLE-XSTREAM-SETUP.md` for detailed troubleshooting guide covering:
- Connectivity issues
- XStream server problems  
- No data in topics
- Performance tuning
- Common error codes

## Reference

- **Confluent Docs:** [Oracle XStream Connector](https://docs.confluent.io/kafka-connectors/oracle-xstream/current/)
- **Oracle Docs:** [XStream Guide](https://docs.oracle.com/en/database/oracle/oracle-database/21/xstrm/)
- **Source Repo:** [confluent-new-cdc-connector](https://github.com/datafisk/confluent-new-cdc-connector)

---

**Integration completed:** April 28, 2026  
**Added support for:** Oracle XE 21c with XStream CDC  
**Compatible with:** Existing IBM MQ connector setup
