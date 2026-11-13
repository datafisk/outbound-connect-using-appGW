# Oracle XStream CDC Connector Setup Guide

> **Scope: Oracle XStream CDC Source connector only.** The Oracle JDBC Source connector has different prerequisites and failure behaviour and is not covered here.

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
oracle_sys_password       = "<ORACLE_PASSWORD>"
oracle_pdb_name           = "XEPDB1"

# Oracle Backend for Application Gateway
oracle_backend_targets = []  # Will be populated automatically

# Oracle XStream Connector
create_oracle_connector = true
oracle_db_password      = "<XSTREAM_PASSWORD>"  # XStream user password
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
- Oracle Database 19c or 21c, standalone or RAC (for RAC, follow [XStream on Oracle RAC](#xstream-on-oracle-rac) below)
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

## XStream on Oracle RAC

Validated on a 2-node Oracle 19c RAC (OCI DB System) behind an Azure Application Gateway TCP listener. Failure behaviour is in [HA-TESTING-XSTREAM.md](./HA-TESTING-XSTREAM.md).

### How the connection works

```
Confluent connector
  -> Egress Access Point -> DNS name (egress DNS record) -> AppGW private frontend :1521
  -> AppGW TCP backend pool = node VIPs (e.g. 10.0.1.167, 10.0.1.38)
  -> node listener on the VIP -> database service (registered on EVERY instance)
```

Do not point the pool at the SCAN VIP. The SCAN listener answers with a redirect to a node VIP or an Oracle-internal host name that Confluent cannot resolve, so the client cannot follow it. Pointing the pool at the node VIPs means the node listener serves the connection directly and no redirect occurs. `REMOTE_LISTENER` does not need to change.

### 1. Database prerequisites (run on one node, as SYSDBA)

```sql
-- ARCHIVELOG must be on
SELECT log_mode FROM v$database;

ALTER SYSTEM SET enable_goldengate_replication = TRUE SCOPE = BOTH SID = '*';
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
-- streams pool: leave Oracle to auto-size, or set explicitly (for example 256M) on every instance
```

Create the XStream administrator in the CDB (common user, name must start with `C##`), then grant XStream admin privileges following the [Confluent Oracle XStream prerequisites](https://docs.confluent.io/cloud/current/connectors/cc-oracle-xstream-cdc-source.html) and Oracle's `DBMS_XSTREAM_AUTH.GRANT_ADMIN_PRIVILEGE`. Oracle password profiles may require two or more special characters.

Create the schema and the capture tables in the PDB. Enable supplemental logging for the tables (`ALTER TABLE ... ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS`) so that updates and deletes carry full row images.

### 2. Create the outbound server (as `C##GGADMIN` in the CDB)

```sql
DECLARE
  tables  DBMS_UTILITY.UNCL_ARRAY;
  schemas DBMS_UTILITY.UNCL_ARRAY;
BEGIN
  tables(1) := 'ORDERMGMT.ORDERS';
  tables(2) := 'ORDERMGMT.ORDER_ITEMS';
  tables(3) := 'ORDERMGMT.CUSTOMERS';
  tables(4) := 'ORDERMGMT.PRODUCTS';
  DBMS_XSTREAM_ADM.CREATE_OUTBOUND(
    server_name     => 'XOUT',
    source_container_name => '<PDB_NAME>',
    table_names     => tables,
    schema_names    => schemas);
END;
/
```

`CREATE_OUTBOUND` creates the capture process, the queue and the outbound server. Check:

```sql
SELECT server_name, capture_name, queue_name, connect_user, status FROM dba_xstream_outbound;
SELECT capture_name, status FROM dba_capture;
```

Expected: capture `ENABLED`, outbound server `DETACHED` until a client attaches, then `ATTACHED`.

Status values: `DETACHED` (enabled, no client), `ATTACHED` (client connected), `DISABLED` (stopped, needs `dbms_xstream_adm.start_outbound`), `ABORTED`.

### 3. Database service for the connector

Use a service that exists on **all** instances. The default CDB service (`<db_unique_name>.<db_domain>`) is registered on every instance and works. If you create a dedicated service, add it to every instance:

```bash
srvctl add service -db <db_unique_name> -service xstrcdb -preferred RACDB1,RACDB2
srvctl start service -db <db_unique_name> -service xstrcdb
```

A service on one instance only breaks connector configuration validation (`ORA-12514`), see [HA-TESTING-XSTREAM.md](./HA-TESTING-XSTREAM.md#5-single-instance-service-does-not-work-hb11).

### 4. Application Gateway

Backend pool = the node VIPs (not SCAN, not host IPs). TCP listener on 1521 and a TCP backend setting with idle timeout 900 s. Commands for TCP listeners and rules use `az network application-gateway routing-rule` (not `rule`). See [APPGW-SETUP.md](../../oracle-rac/docs/APPGW-SETUP.md).

Notes:
- `az network application-gateway show-backend-health` returns nothing for TCP pools. Test each VIP directly from a VM in the AppGW subnet instead (`nc -zv <vip> 1521`).
- The TCP probe only checks that the port accepts connections. It cannot detect a missing database service.
- Make sure the OCI VCN CIDR is listed on exactly **one** Azure local network gateway or route. An overlap with another site-to-site connection on the same hub gateway causes intermittent `ORA-12170` and lost flows.
- Allow TCP 1521 from the AppGW subnet to the VIPs in the OCI security list or NSG.

### 5. Connector settings

| Setting | Value |
|---------|-------|
| `database.hostname` | Egress DNS name that resolves to the AppGW frontend |
| `database.port` | 1521 |
| `database.service.name` | The CDB service from step 3 |
| `database.dbname` | CDB name (for example `RACDB`) |
| `database.pdb.name` | PDB name |
| `database.out.server.name` | `XOUT` |
| `table.include.list` | `ORDERMGMT[.](ORDERS|ORDER_ITEMS|CUSTOMERS|PRODUCTS)` |

### 6. Verify end to end

```sql
-- in the PDB, as the schema owner
INSERT INTO ordermgmt.customers (...) VALUES (...);
COMMIT;
```

The row appeared on `<topic.prefix>.ORDERMGMT.CUSTOMERS` about 3 s later in testing.

### Single-instance RAC

With one node and one VIP the pool has a single backend and the steps above are unchanged. Register the service on that node. For RAC One Node (service on one node at a time) use a pool with only the active node's VIP; a pool with both VIPs fails with ORA-12514 on reconnect (see [HA-TESTING-XSTREAM.md](./HA-TESTING-XSTREAM.md#single-node-deployments)).

### 7. Operating a RAC with XStream

- Monitor `dba_xstream_outbound.status` (expect `ATTACHED`) and lag. Connector status alone can read RUNNING while the outbound server is DISABLED.
- After a node restart, check XStream status. If `DISABLED`, run `EXEC dbms_xstream_adm.start_outbound('XOUT');`, then pause the connector, wait until the pause has applied and the old `C##GGADMIN` session has disappeared from `gv$session`, then resume it. Do not wait for the session before pausing: a stalled task keeps its database connection until the pause takes effect.
- See [HA-TESTING-XSTREAM.md](./HA-TESTING-XSTREAM.md) for the measured behaviour in six failure scenarios.

---

## Post-Deployment Steps

### 1. Create XStream Outbound Server

After Oracle is provisioned, create the XStream outbound server:

```bash
# SSH to Oracle VM (get IP from terraform output)
ssh oracleadmin@$(terraform output -raw oracle_public_ip)

# Connect to Oracle as XStream admin
docker exec -it oracle21c sqlplus C##GGADMIN/<XSTREAM_PASSWORD>@XE

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
XOUT         CAPTURE$...   C##GGADMIN    DETACHED
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
docker exec -it oracle21c sqlplus C##GGADMIN/<XSTREAM_PASSWORD>@XE

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
docker exec -it oracle21c sqlplus ordermgmt/<ORDERMGMT_PASSWORD>@XEPDB1

-- Insert test data
INSERT INTO ORDERS (order_id, customer_id, order_date, order_total, status)
VALUES (seq_order_id.NEXTVAL, 1, SYSDATE, 100.00, 'NEW');
COMMIT;

-- Or use data generator
EXEC generate_orders(10);
```

### Common Issues

**1. Connector fails: "ORA-01017: invalid username/password"**
- Verify XStream user password: `oracle_db_password = "<XSTREAM_PASSWORD>"`
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
