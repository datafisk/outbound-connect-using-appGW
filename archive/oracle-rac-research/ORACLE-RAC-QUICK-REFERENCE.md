# Oracle RAC Quick Reference Card

Quick reference for Oracle RAC deployment commands and troubleshooting.

## Prerequisites

```bash
# Check Azure quota
az vm list-usage --location westus2 \
    --query "[?contains(name.value, 'standardDSv3Family')]" -o table

# Need: 26 cores minimum
# If insufficient, request increase at:
# Portal > Subscriptions > Usage + quotas
```

## Deployment Commands

### 1. Deploy Infrastructure

```bash
# Validate configuration
terraform validate

# Review plan
terraform plan | grep oracle_rac

# Deploy (will fail if quota insufficient)
terraform apply

# Get node IPs
terraform output | grep oracle_rac
```

### 2. Upload Oracle Software

```bash
# Node 1 IP from Terraform output
NODE1_IP=$(terraform output -raw oracle_rac_node1_private_ip)

# Upload Grid Infrastructure
scp -i ./ssl-certs/oracle-rac-key \
    ~/Downloads/LINUX.X64_193000_grid_home.zip \
    confluent@${NODE1_IP}:/tmp/

# Upload Database Software
scp -i ./ssl-certs/oracle-rac-key \
    ~/Downloads/LINUX.X64_193000_db_home.zip \
    confluent@${NODE1_IP}:/tmp/
```

### 3. Configure ASM Disks (Both Nodes)

```bash
# Node 1
ssh -i ./ssl-certs/oracle-rac-key confluent@${NODE1_IP}
sudo /u01/configure-asm-disks.sh
ls -l /dev/oracleasm/  # Verify 9 disks

# Node 2
NODE2_IP=$(terraform output -raw oracle_rac_node2_private_ip)
ssh -i ./ssl-certs/oracle-rac-key confluent@${NODE2_IP}
sudo /u01/configure-asm-disks.sh
ls -l /dev/oracleasm/  # Verify 9 disks
```

### 4. Install Grid Infrastructure (Node 1 Only)

```bash
# On Node 1
sudo su - grid
/u01/install-grid-infrastructure.sh

# When prompted, run on BOTH nodes:
# Node 1:
sudo /u01/app/oraInventory/orainstRoot.sh
sudo /u01/app/19.3.0/grid/root.sh

# Node 2:
sudo /u01/app/oraInventory/orainstRoot.sh
sudo /u01/app/19.3.0/grid/root.sh

# Verify
/u01/app/19.3.0/grid/bin/crsctl check cluster -all
```

### 5. Install Database (Node 1 Only)

```bash
# On Node 1
sudo su - oracle
/u01/install-database.sh RACDB RACPDB1 Confluent123!

# When prompted, run on BOTH nodes:
# Node 1:
sudo /u01/app/oracle/product/19.3.0/dbhome_1/root.sh

# Node 2:
sudo /u01/app/oracle/product/19.3.0/dbhome_1/root.sh

# Verify
/u01/app/19.3.0/grid/bin/srvctl status database -d RACDB
```

### 6. Configure XStream (Node 1 Only)

```bash
# On Node 1
sudo su - oracle
/u01/configure-xstream.sh RACDB RACPDB1 Confluent123! \
    C##GGADMIN Confluent12! XOUT ORDERMGMT Confluent123!

# Verify
sqlplus sys/Confluent123!@rac-scan:1521/RACPDB1 as sysdba
SQL> SELECT server_name, status FROM DBA_XSTREAM_OUTBOUND;
```

### 7. Update Application Gateway

```bash
# Get SCAN IP
ssh confluent@${NODE1_IP} "cat /etc/hosts | grep rac-scan"
# Should show: 172.200.20.16    rac-scan.internal         rac-scan

# Update terraform.tfvars
cat >> terraform.tfvars <<EOF
oracle_backend_targets = ["172.200.20.16"]
EOF

# Apply changes
terraform apply
```

## Health Check Commands

### Cluster Status

```bash
# Overall cluster health
/u01/app/19.3.0/grid/bin/crsctl check cluster -all

# All resources
/u01/app/19.3.0/grid/bin/crsctl stat res -t

# Quick status script
/u01/check-rac-status.sh
```

### ASM Status

```bash
# ASM instances
/u01/app/19.3.0/grid/bin/srvctl status asm

# Disk groups
/u01/app/19.3.0/grid/bin/asmcmd lsdg

# Disk space
/u01/app/19.3.0/grid/bin/asmcmd lsdsk
```

### Database Status

```bash
# Database instances
/u01/app/19.3.0/grid/bin/srvctl status database -d RACDB

# Listener
/u01/app/19.3.0/grid/bin/srvctl status listener

# SCAN listener
/u01/app/19.3.0/grid/bin/srvctl status scan_listener

# Database connection
sqlplus sys/Confluent123!@rac-scan:1521/RACDB as sysdba
SQL> SELECT instance_name, host_name, status FROM gv$instance;
```

### XStream Status

```bash
sqlplus sys/Confluent123!@rac-scan:1521/RACPDB1 as sysdba

SQL> ALTER SESSION SET CONTAINER=RACPDB1;

SQL> SELECT server_name, status, capture_name
     FROM DBA_XSTREAM_OUTBOUND;

SQL> SELECT capture_name, status
     FROM DBA_CAPTURE;

SQL> SELECT COUNT(*) FROM ORDERMGMT.CUSTOMERS;
```

## Troubleshooting

### ASM Disks Not Visible

```bash
# Check disk attachment
lsblk | grep sd

# Should see sdc-sdk (9 shared disks)

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger
sleep 3
ls -l /dev/oracleasm/
```

### Grid Installation Fails

```bash
# Check logs
tail -f /u01/app/grid/logs/grid_install_*.log

# Verify /etc/hosts
cat /etc/hosts | grep rac

# Verify SSH
sudo su - grid
ssh confluent-pl-rac-node2 hostname
```

### Database Won't Start

```bash
# Check alert log
tail -f $ORACLE_BASE/diag/rdbms/racdb/RACDB1/trace/alert_RACDB1.log

# Check cluster services
/u01/app/19.3.0/grid/bin/crsctl stat res -t

# Restart database
/u01/app/19.3.0/grid/bin/srvctl stop database -d RACDB
/u01/app/19.3.0/grid/bin/srvctl start database -d RACDB
```

### XStream Server Not Running

```bash
sqlplus / as sysdba
ALTER SESSION SET CONTAINER=RACPDB1;

-- Check capture process
SELECT capture_name, status FROM DBA_CAPTURE;

-- Start capture
BEGIN
    DBMS_CAPTURE_ADM.START_CAPTURE(capture_name => 'CAPTURE$_1');
END;
/

-- Start XStream
BEGIN
    DBMS_XSTREAM_ADM.START_OUTBOUND(server_name => 'XOUT');
END;
/
```

### Connection Issues via AppGW

```bash
# Check backend health
az network application-gateway show-backend-health \
    -g vpc-peered-cce-se \
    -n confluent-pl-appgw \
    --query "backendAddressPools[?name=='oracle-backend-pool']"

# Test from RAC node
sqlplus sys/Confluent123!@rac-scan:1521/RACPDB1 as sysdba

# Check listener
/u01/app/19.3.0/grid/bin/lsnrctl status LISTENER_SCAN1
```

## Common File Locations

| Path | Description |
|------|-------------|
| `/u01/app/19.3.0/grid` | Grid Infrastructure home |
| `/u01/app/oracle/product/19.3.0/dbhome_1` | Oracle Database home |
| `/u01/stage/grid` | Grid software staging |
| `/u01/stage/database` | Database software staging |
| `/dev/oracleasm/` | ASM disk devices |
| `/u01/app/grid/logs/` | Installation logs |
| `$ORACLE_BASE/diag/rdbms/` | Database diagnostic logs |
| `/etc/hosts` | Network configuration |

## Important IPs

| Component | IP Address | Purpose |
|-----------|------------|---------|
| Node 1 Public | 172.200.20.10 | SSH, client connections |
| Node 2 Public | 172.200.20.11 | SSH, client connections |
| Node 1 Private | 172.200.21.10 | Cluster heartbeat |
| Node 2 Private | 172.200.21.11 | Cluster heartbeat |
| Node 1 Interconnect | 172.200.22.10 | Cache Fusion |
| Node 2 Interconnect | 172.200.22.11 | Cache Fusion |
| Node 1 VIP | 172.200.20.14 | Failover VIP |
| Node 2 VIP | 172.200.20.15 | Failover VIP |
| SCAN | 172.200.20.16 | Client access point |

## Default Credentials

| Component | Username | Password |
|-----------|----------|----------|
| OS Admin | confluent | SSH key auth |
| Grid User | grid | Confluent123! |
| Oracle User | oracle | Confluent123! |
| SYS/SYSTEM | sys/system | Confluent123! |
| XStream Admin | C##GGADMIN | Confluent12! |
| Test Schema | ORDERMGMT | Confluent123! |

## Useful SQL Queries

```sql
-- Check RAC configuration
SELECT instance_name, host_name, status, database_status
FROM gv$instance
ORDER BY instance_number;

-- Check ASM disk groups
SELECT name, state, type, total_mb, free_mb
FROM v$asm_diskgroup;

-- Check database services
SELECT name, pdb, network_name
FROM dba_services
WHERE name NOT LIKE 'SYS%'
ORDER BY name;

-- Check XStream capture progress
SELECT capture_name, status, state, logminer_id
FROM dba_capture;

-- Check table capture rules
SELECT capture_name, rule_set_name, rule_name
FROM dba_capture;

-- Monitor XStream performance
SELECT apply_name, total_messages, total_txns
FROM v$streams_apply_coordinator;
```

## Test CDC

```sql
-- Connect to PDB
sqlplus ORDERMGMT/Confluent123!@rac-scan:1521/RACPDB1

-- Insert test record
INSERT INTO CUSTOMERS VALUES (
    customer_seq.NEXTVAL,
    'Test User ' || TO_CHAR(SYSDATE, 'HH24:MI:SS'),
    'test@example.com',
    '555-TEST',
    '123 Test Ave',
    'TestCity',
    'TC',
    'USA',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
);
COMMIT;

-- Update record
UPDATE CUSTOMERS
SET email = 'updated@example.com'
WHERE customer_name LIKE 'Test User%';
COMMIT;

-- Delete record
DELETE FROM CUSTOMERS
WHERE customer_name LIKE 'Test User%';
COMMIT;
```

## Key Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 1521 | TCP | Oracle TNS Listener |
| 5353 | UDP | mDNS for SCAN |
| 42424 | TCP | Grid Control |

## Service Management

```bash
# Stop/Start Grid Infrastructure
/u01/app/19.3.0/grid/bin/crsctl stop crs
/u01/app/19.3.0/grid/bin/crsctl start crs

# Stop/Start Database
/u01/app/19.3.0/grid/bin/srvctl stop database -d RACDB
/u01/app/19.3.0/grid/bin/srvctl start database -d RACDB

# Stop/Start ASM
/u01/app/19.3.0/grid/bin/srvctl stop asm
/u01/app/19.3.0/grid/bin/srvctl start asm

# Stop/Start Listener
/u01/app/19.3.0/grid/bin/srvctl stop listener
/u01/app/19.3.0/grid/bin/srvctl start listener
```

## Emergency Procedures

### Cluster Won't Start

```bash
# Check logs
tail -f /u01/app/grid/diag/crs/$(hostname)/crs/trace/alert.log

# Force start
/u01/app/19.3.0/grid/bin/crsctl start crs -excl -nocrs
```

### Database Recovery

```bash
# Mount database
sqlplus / as sysdba
STARTUP MOUNT;

# Check datafiles
SELECT file#, status, name FROM v$datafile;

# Open database
ALTER DATABASE OPEN;
```

### ASM Disk Issues

```bash
# Check disk status
/u01/app/19.3.0/grid/bin/asmcmd lsdsk -p

# Rebalance disk group
ALTER DISKGROUP DATA REBALANCE POWER 10;
```

## Documentation Links

- [Complete Deployment Guide](ORACLE-RAC-DEPLOYMENT-GUIDE.md)
- [Architecture Overview](ORACLE-RAC-SETUP.md)
- [Files Summary](ORACLE-RAC-FILES-SUMMARY.md)
- [Module README](modules/oracle-rac/README.md)

## Support

For issues, check:
- Installation logs: `/u01/app/grid/logs/`
- Database alert log: `$ORACLE_BASE/diag/rdbms/racdb/RACDB1/trace/alert_RACDB1.log`
- Grid logs: `/u01/app/grid/diag/crs/`
- Terraform state: `terraform.tfstate`
