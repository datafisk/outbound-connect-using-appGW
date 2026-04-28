# Oracle XStream CDC Connector Setup Guide

This guide explains how to set up Oracle Database with XStream CDC and connect it to Confluent Cloud via Private Link through Azure Application Gateway.

## Architecture

```
Confluent Cloud
  ↓ (Egress Private Link)
Azure Application Gateway
  ├─ Port 1414 → IBM MQ Backend
  └─ Port 1521 → Oracle Database Backend
       ↓
Oracle XE 21c (Docker on Azure VM)
  ├─ XStream Outbound Server (XOUT)
  └─ Schema: ORDERMGMT (sample data)
```

## Deployment Options

### Option 1: Provision Oracle Database Automatically (Recommended for PoC)

Terraform will create an Azure VM with Oracle XE 21c in Docker, fully configured for XStream CDC.

**What gets created:**
- ✅ Azure VM (Standard_D4s_v3) with Ubuntu
- ✅ Docker with Oracle XE 21c container
- ✅ Archive log mode enabled
- ✅ Supplemental logging configured
- ✅ XStream users created (C##GGADMIN, C##CFLTUSER)
- ✅ Sample schema (ORDERMGMT) with data
- ✅ NSG rules (Oracle 1521 from App Gateway subnet)

**Configuration in `terraform.tfvars`:**

```hcl
# Oracle Database Provisioning
provision_oracle_database = true
oracle_ssh_public_key     = file("~/.ssh/id_rsa.pub")
oracle_sys_password       = "Confluent123!"
oracle_pdb_name           = "XEPDB1"

# Oracle Backend for Application Gateway
oracle_backend_targets = []  # Will be populated automatically

# Oracle XStream Connector
create_oracle_connector = true
oracle_db_password      = "Confluent12!"  # XStream user password
oracle_table_include_list = "ORDERMGMT[.](ORDERS|CUSTOMERS|PRODUCTS)"
```

**Deploy:**

```bash
terraform init
terraform plan
terraform apply
```

**Oracle will be:**
- Private IP: Auto-assigned from VNet
- Public IP: Created for SSH access (optional)
- Automatically added to Application Gateway backend

---

### Option 2: Use Existing Oracle Database

If you already have Oracle Database running, configure it for XStream and point the connector to it.

**Prerequisites:**
- Oracle Database 19c, 21c, or 23ai
- Network access from Application Gateway subnet
- XStream configured (see below)

**Configuration in `terraform.tfvars`:**

```hcl
# Skip Oracle provisioning
provision_oracle_database = false

# Point to existing Oracle
oracle_backend_targets = ["10.0.5.10"]  # Your Oracle IP

# Oracle XStream Connector
create_oracle_connector   = true
oracle_db_hostname        = "10.0.5.10"  # Or DNS name if created
oracle_db_password        = "your-xstream-password"
oracle_db_name            = "ORCLCDB"
oracle_pdb_name           = "ORCLPDB1"
oracle_out_server_name    = "XOUT"
```

**Manual XStream Setup:**

If using an existing Oracle database, run the setup scripts:

```bash
# Copy scripts to Oracle server
scp -r modules/oracle-database/scripts oracle-server:/tmp/

# SSH to Oracle server
ssh oracle-server

# Run setup (adjust for your Oracle version)
cd /tmp/scripts
./00_setup_cdc.sh "YourSysPassword" "ORCLPDB1"
```

---

## Post-Deployment Steps

### 1. Create XStream Outbound Server

After Oracle is provisioned, create the XStream outbound server:

```bash
# SSH to Oracle VM (get IP from terraform output)
ssh oracleadmin@$(terraform output -raw oracle_public_ip)

# Connect to Oracle as XStream admin
docker exec -it oracle21c sqlplus C##GGADMIN/Confluent12!@XE

# Create XStream outbound server
BEGIN
  DBMS_XSTREAM_ADM.CREATE_OUTBOUND(
    server_name     => 'XOUT',
    table_names     => 'ORDERMGMT.ORDERS,ORDERMGMT.CUSTOMERS,ORDERMGMT.PRODUCTS',
    source_database => 'XEPDB1'
  );
END;
/

# Verify server created
SELECT server_name, capture_name, connect_user, status 
FROM DBA_XSTREAM_OUTBOUND;

# Exit
EXIT;
```

**Expected output:**
```
SERVER_NAME  CAPTURE_NAME  CONNECT_USER  STATUS
XOUT         CAPTURE$...   C##GGADMIN    DISABLED
```

### 2. Add Oracle Backend to Application Gateway

If Oracle was provisioned automatically, this is done for you. Otherwise, update `terraform.tfvars`:

```hcl
oracle_backend_targets = ["<oracle-private-ip>"]
```

Then apply:
```bash
terraform apply
```

### 3. Create DNS Record (Optional)

For a friendly hostname:

```hcl
# terraform.tfvars
create_dns_record  = true
oracle_dns_domain  = "oracle.yourdomain.com"
```

### 4. Deploy Oracle XStream Connector

The connector deploys automatically with `create_oracle_connector = true`.

**Verify deployment:**
```bash
# Check connector status
terraform output oracle_connector_status

# Or via Confluent CLI
confluent connect list
confluent connect describe <connector-id>
```

---

## Monitoring & Troubleshooting

### Check Oracle Connectivity

From a VM in the App Gateway subnet:
```bash
nc -zv <oracle-ip> 1521
telnet <oracle-ip> 1521
```

### Check XStream Server Status

```bash
# SSH to Oracle VM
ssh oracleadmin@<oracle-ip>

# Check container
docker ps
docker logs oracle21c

# Connect to Oracle
docker exec -it oracle21c sqlplus C##GGADMIN/Confluent12!@XE

# Check XStream status
SELECT server_name, capture_name, status, status_change_time
FROM DBA_XSTREAM_OUTBOUND;

# Check capture process
SELECT capture_name, status, captured_scn, applied_scn
FROM DBA_XSTREAM_OUTBOUND_PROGRESS;
```

### View Captured Changes

```bash
# Consume from Kafka topics
kafka-console-consumer --bootstrap-server <bootstrap> \
  --topic oracle.ORDERMGMT.ORDERS \
  --from-beginning
```

### Generate Test Data

```sql
-- Connect to PDB
docker exec -it oracle21c sqlplus ordermgmt/kafka@XEPDB1

-- Insert test data
INSERT INTO ORDERS (order_id, customer_id, order_date, order_total, status)
VALUES (seq_order_id.NEXTVAL, 1, SYSDATE, 100.00, 'NEW');
COMMIT;

-- Or use data generator
EXEC generate_orders(10);
```

### Common Issues

**1. Connector fails: "ORA-01017: invalid username/password"**
- Verify XStream user password: `oracle_db_password = "Confluent12!"`
- Check user exists: `SELECT * FROM DBA_USERS WHERE USERNAME = 'C##GGADMIN';`

**2. No data in topics**
- Verify XStream server is capturing: Check `DBA_XSTREAM_OUTBOUND` status
- Check table is in capture list: `TABLE_INCLUDE_LIST` pattern matches
- Ensure supplemental logging: `SELECT * FROM DBA_LOG_GROUPS WHERE OWNER = 'ORDERMGMT';`

**3. Connection timeout**
- Check NSG allows App Gateway subnet → Oracle (port 1521)
- Verify Oracle listener: `docker exec oracle21c lsnrctl status`
- Check Private Link endpoint is approved

**4. XStream server status: ABORTED**
- Check Oracle alert log: `docker exec oracle21c tail -100 /opt/oracle/diag/rdbms/xe/XE/trace/alert_XE.log`
- Verify archive log space: `SELECT * FROM V$RECOVERY_FILE_DEST;`

---

## Performance Tuning

For high-volume capture:

```hcl
# terraform.tfvars - Connector performance tuning
oracle_snapshot_fetch_size = "50000"
connector_tasks_max        = "4"  # More tasks if capturing multiple schemas
```

**Oracle SGA tuning** (for VM-provisioned Oracle):

```hcl
# Increase memory for better performance
oracle_memory_mb = 8000  # Default is 4000 MB
oracle_vm_size   = "Standard_D8s_v3"  # 8 vCPUs, 32 GB RAM
```

---

## Cost Estimate (Option 1: Provisioned Oracle)

- Application Gateway Standard_v2: ~$90-110/month (shared with IBM MQ)
- Oracle VM (Standard_D4s_v3): ~$140/month
- Storage (256 GB Premium SSD): ~$30/month
- **Total additional cost for Oracle: ~$170/month**

**Cost Savings:**
- No Oracle license fees (XE edition is free)
- Shared Application Gateway (vs dedicated: saves ~$100/month)
- Auto-shutdown Oracle VM when not in use to save costs

---

## Security Recommendations

### Production Deployment

1. **Remove Public IP** from Oracle VM:
   ```hcl
   create_public_ip = false
   ```
   Access via Bastion Host or VPN instead.

2. **Restrict NSG** to specific IPs:
   ```hcl
   allowed_ssh_cidr = "your.corporate.ip/32"
   ```

3. **Use Azure Key Vault** for passwords:
   ```hcl
   oracle_sys_password = data.azurerm_key_vault_secret.oracle_sys.value
   ```

4. **Enable Oracle TDE** (Transparent Data Encryption):
   ```sql
   -- In Oracle
   ALTER PLUGGABLE DATABASE XEPDB1 OPEN;
   ADMINISTER KEY MANAGEMENT SET KEYSTORE CLOSE;
   ```

---

## Next Steps

- ✅ Oracle Database provisioned and configured
- ✅ XStream outbound server created
- ✅ Application Gateway backend configured
- ✅ Connector deployed

**What's next:**
1. Monitor connector: `confluent connect describe <connector-id>`
2. View captured data in Kafka topics
3. Add more tables to capture list
4. Configure downstream consumers

**Reference Documentation:**
- [Confluent Oracle XStream Connector](https://docs.confluent.io/kafka-connectors/oracle-xstream/current/)
- [Oracle XStream Guide](https://docs.oracle.com/en/database/oracle/oracle-database/21/xstrm/)
- Setup scripts: `modules/oracle-database/scripts/`
