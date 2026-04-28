# Oracle XStream CDC Source Connector

This directory contains configuration for the Confluent Oracle XStream CDC Source Connector, which captures change data from Oracle Database using the XStream API.

## Overview

The Oracle XStream connector:
- ✅ Captures **INSERT**, **UPDATE**, **DELETE** operations in real-time
- ✅ Supports initial snapshot of existing data
- ✅ Works with Oracle 19c, 21c XE, 23ai, and Enterprise Edition
- ✅ Uses Oracle XStream API (requires Oracle GoldenGate license for EE)
- ✅ Connects via **Private Link** through Application Gateway

## Prerequisites

### Oracle Database Requirements

1. **XStream configured** (see `../../modules/oracle-database/` for automated setup)
2. **Archive log mode enabled**
3. **Supplemental logging enabled**
4. **XStream user created** (`C##GGADMIN` with appropriate privileges)
5. **XStream outbound server created** (`XOUT` or custom name)
6. **Application user and schema** (`ORDERMGMT` with sample data)

### Network Requirements

1. **Oracle accessible from Application Gateway subnet**
2. **NSG allows TCP 1521 from App Gateway subnet**
3. **Private Link endpoint approved** (Confluent Cloud → App Gateway)
4. **(Optional) DNS record created** for friendly hostname

## Configuration

### Step 1: Copy Environment File

```bash
cd connectors/oracle-xstream
cp oracle-xstream.env.example oracle-xstream.env
```

### Step 2: Update Configuration

Edit `oracle-xstream.env`:

```bash
# Oracle Connection (use DNS name or Private Link IP)
ORACLE_HOSTNAME="oracle.yourdomain.com"  # From terraform output
ORACLE_PORT="1521"
ORACLE_USER="C##GGADMIN"
ORACLE_PASSWORD="Confluent12!"
ORACLE_DBNAME="XE"
ORACLE_PDB_NAME="XEPDB1"

# Kafka Configuration
KAFKA_CLUSTER_ID="lkc-xxxxx"
KAFKA_API_KEY="your-key"
KAFKA_API_SECRET="your-secret"

# Tables to capture
TABLE_INCLUDE_LIST="ORDERMGMT[.](ORDERS|CUSTOMERS|PRODUCTS)"
```

### Step 3: Deploy with Terraform

The connector is deployed automatically when you set:

```hcl
# terraform.tfvars
create_oracle_connector = true
oracle_db_hostname      = "oracle.yourdomain.com"
oracle_db_password      = "Confluent12!"
```

Then run:
```bash
terraform apply
```

**Or deploy manually via Confluent CLI:**

```bash
# Generate connector JSON
./generate-config.sh

# Create connector
confluent connect create --config oracle-xstream.generated.json
```

## Monitoring

### Check Connector Status

```bash
# Via Confluent CLI
confluent connect list
confluent connect describe <connector-id>

# Via Terraform
terraform output oracle_connector_status
```

### Monitor Oracle XStream

SSH into the Oracle VM:
```bash
ssh oracleadmin@<oracle-public-ip>

# Connect to Oracle
docker exec -it oracle21c sqlplus C##GGADMIN/Confluent12!@XE

# Check XStream server status
SQL> SELECT server_name, capture_name, connect_user, queue_owner, queue_name, 
     start_scn, status, status_change_time 
     FROM DBA_XSTREAM_OUTBOUND;

# Check XStream statistics
SQL> SELECT * FROM V$XSTREAM_OUTBOUND_SERVER;
```

### View Captured Data

```bash
# Consume from topics
kafka-console-consumer --bootstrap-server <bootstrap-server> \
  --topic oracle.ORDERMGMT.ORDERS \
  --from-beginning
```

## Troubleshooting

### Connector Fails to Start

**Check Oracle connectivity from App Gateway:**
```bash
# From a VM in the App Gateway subnet
nc -zv <oracle-ip> 1521
```

**Verify XStream server is running:**
```sql
SELECT server_name, status FROM DBA_XSTREAM_OUTBOUND;
-- Status should be 'ATTACHED' or 'CAPTURING'
```

### No Data in Topics

**Check XStream position:**
```sql
SELECT applied_scn, oldest_position 
FROM DBA_XSTREAM_OUTBOUND_PROGRESS 
WHERE server_name = 'XOUT';
```

**Verify table has supplemental logging:**
```sql
SELECT owner, table_name, log_group_type, supplemental_log_data_min
FROM DBA_LOG_GROUPS
WHERE owner = 'ORDERMGMT';
```

**Generate test data:**
```sql
-- Execute data generator
EXEC ORDERMGMT.generate_orders(10);
COMMIT;
```

### Connection Timeouts

1. **Check NSG rules** allow traffic from App Gateway subnet
2. **Verify Private Link endpoint** is approved
3. **Check Oracle listener** is running:
   ```bash
   docker exec oracle21c lsnrctl status
   ```

## Schema Evolution

The connector handles schema changes:
- ✅ **Adding columns**: Automatically captured with NULL for existing rows
- ✅ **Dropping columns**: Removed from captured data
- ⚠️ **Renaming columns**: Treated as drop + add
- ⚠️ **Changing data types**: May require connector restart

## Performance Tuning

For high-volume tables:

```bash
# Increase batch sizes
MAX_BATCH_SIZE="32768"
PRODUCER_BATCH_SIZE="409600"

# Increase fetch sizes
SNAPSHOT_FETCH_SIZE="50000"
QUERY_FETCH_SIZE="50000"

# Add more tasks (if multiple tables)
TASKS_MAX="4"
```

## Reference

- [Oracle XStream Connector Documentation](https://docs.confluent.io/kafka-connectors/oracle-xstream/current/overview.html)
- [Oracle XStream Concepts](https://docs.oracle.com/en/database/oracle/oracle-database/21/xstrm/xstream-concepts.html)
- XStream setup scripts: `../../modules/oracle-database/scripts/`
