# Oracle RAC Connector Troubleshooting Guide

Common issues and solutions for Oracle RAC connector deployment with Application Gateway.

## Connection Issues

### Error: "ORA-12514: TNS:listener does not currently know of service requested"

**Symptoms:**
- Connector cannot connect to Oracle RAC
- Error code: ORA-12514
- Occurs especially after node failures or restarts

**Causes:**
1. Service not registered with listener
2. REMOTE_LISTENER not configured correctly
3. Service name typo in connection string
4. Listener not running

**Solutions:**

1. **Verify service is registered:**
```sql
-- On any RAC node
lsnrctl services

-- Should show your service name under each node listener
```

2. **Check REMOTE_LISTENER configuration:**
```sql
SELECT name, value FROM v$parameter WHERE name = 'remote_listener';

-- Must be FQDN, not IP addresses
-- Example: racnode-scan.domain.com:1521
```

3. **Re-register services:**
```sql
-- On each RAC node
ALTER SYSTEM REGISTER;

-- Wait 30 seconds, then check again
lsnrctl services
```

4. **Verify service name in connection string:**
```sql
-- Show all service names
SELECT name FROM v$services WHERE name NOT LIKE 'SYS%';

-- Use exact service name in JDBC URL:
-- jdbc:oracle:thin:@//<host>:1521/<service_name>
```

### Error: "ORA-12170: TNS:Connect timeout occurred"

**Symptoms:**
- Connection times out
- No response from database

**Causes:**
1. Network connectivity issue between AppGW and RAC
2. Firewall blocking port 1521
3. RAC listener not running
4. Wrong IP addresses in AppGW backend pool

**Solutions:**

1. **Test network connectivity from AppGW subnet:**
```bash
# From a VM in the same subnet as AppGW
nc -zv <rac-node-ip> 1521

# Or using telnet
telnet <rac-node-ip> 1521
```

2. **Check RAC listener status:**
```bash
# On each RAC node
lsnrctl status LISTENER

# Should show STATUS: RUNNING
```

3. **Verify AppGW backend pool IPs:**
```bash
az network application-gateway address-pool show \
  --gateway-name <appgw-name> \
  --resource-group <rg> \
  --name <pool-name>

# IPs must match actual RAC node IPs
```

4. **Check firewall rules:**
```bash
# Azure NSG (if RAC on Azure)
az network nsg rule list --nsg-name <nsg-name> --resource-group <rg>

# OCI Security List (if RAC on OCI)
oci network security-list get --security-list-id <id>
```

### Error: "IO Error: The Network Adapter could not establish the connection"

**Symptoms:**
- Intermittent connection failures
- Works sometimes, fails others

**Causes:**
1. AppGW health probe marking nodes as unhealthy
2. Load balancer distributing to failed node
3. Network instability

**Solutions:**

1. **Check AppGW backend health:**
```bash
az network application-gateway show-backend-health \
  --name <appgw-name> \
  --resource-group <rg>

# All nodes should show "Healthy"
```

2. **Review health probe configuration:**
```bash
# Probe should match your RAC setup
# For RAC on port 1521:
Protocol: TCP
Port: 1521
Interval: 30 seconds
Unhealthy threshold: 3
```

3. **Check RAC node status:**
```sql
SELECT inst_id, instance_name, host_name, status 
FROM gv$instance 
ORDER BY inst_id;

-- All should show STATUS = OPEN
```

---

## Service Registration Issues

### Services Not Appearing in lsnrctl

**Symptoms:**
- `lsnrctl services` shows empty or missing services
- Connector cannot find database service

**Causes:**
1. REMOTE_LISTENER not set
2. Services not started
3. Listener configuration issue

**Solutions:**

1. **Set REMOTE_LISTENER on all nodes:**
```sql
-- MUST use FQDN, not IPs
ALTER SYSTEM SET REMOTE_LISTENER='racnode-scan.domain.com:1521' SCOPE=BOTH SID='*';

-- Register immediately
ALTER SYSTEM REGISTER;
```

2. **Verify service is started:**
```sql
SELECT name, enabled FROM v$services;

-- If service is disabled:
BEGIN
  DBMS_SERVICE.START_SERVICE('<service_name>');
END;
/
```

3. **Check listener configuration:**
```bash
cat $ORACLE_HOME/network/admin/listener.ora

# Should have LISTENER entry for port 1521
```

### REMOTE_LISTENER Shows IPs Instead of FQDN

**Symptoms:**
- `REMOTE_LISTENER` parameter shows IP addresses
- Was set correctly but reverted to IPs

**Cause**: Oracle RAC automatically converts FQDNs to IPs in some configurations

**Solution:**

This is expected behavior in some Oracle versions. The key is that services still register correctly. Verify with:

```sql
-- Check registration is working
lsnrctl services

-- Should show services for all nodes
```

If services aren't registering, use SCAN explicitly:

```sql
ALTER SYSTEM SET REMOTE_LISTENER='<scan-name>:1521' SCOPE=BOTH SID='*';
```

---

## Application Gateway Issues

### All Backend Instances Showing Unhealthy

**Symptoms:**
- AppGW backend health shows all RAC nodes as unhealthy
- Connector cannot connect

**Causes:**
1. Health probe configuration incorrect
2. Network path blocked
3. All RAC nodes actually down

**Solutions:**

1. **Verify health probe settings:**
```bash
az network application-gateway probe show \
  --gateway-name <appgw-name> \
  --resource-group <rg> \
  --name <probe-name>

# For Oracle RAC:
# Protocol: TCP
# Port: 1521
```

2. **Test connectivity from AppGW subnet:**
```bash
# From VM in AppGW subnet
nc -zv <rac-node-1-ip> 1521
nc -zv <rac-node-2-ip> 1521
```

3. **Check RAC listener is listening:**
```bash
# On each RAC node
lsnrctl status | grep "PORT=1521"
```

4. **Review NSG rules:**
```bash
# Ensure AppGW subnet can reach RAC on port 1521
az network nsg rule list \
  --nsg-name <nsg-name> \
  --resource-group <rg> \
  | grep 1521
```

### Load Balancing Appears Uneven

**Symptoms:**
- All connections going to one RAC node
- Other nodes sitting idle

**Cause**: Using round-robin instead of least-connections

**Solution:**

```bash
# Change to least-connections
az network application-gateway address-pool update \
  --gateway-name <appgw-name> \
  --resource-group <rg> \
  --name <pool-name> \
  --lb-algorithm LeastConnections
```

---

## Failover Issues

### Connector Fails When RAC Node Goes Down

**Symptoms:**
- RAC node shuts down
- Connector goes to FAILED state
- Doesn't recover automatically

**Causes:**
1. Health probe interval too long
2. Connector not configured for retries
3. Active connection to failed node

**Solutions:**

1. **Reduce health probe interval:**
```bash
# Update probe to detect failures faster
az network application-gateway probe update \
  --gateway-name <appgw-name> \
  --resource-group <rg> \
  --name <probe-name> \
  --interval 10 \
  --threshold 2

# This marks unhealthy nodes in ~20 seconds
```

2. **Configure connector retry logic:**
```json
{
  "errors.retry.timeout": "300000",
  "errors.retry.delay.max.ms": "60000"
}
```

3. **Restart connector if needed:**
```bash
confluent connect cluster pause <connector-id>
# Wait 10 seconds
confluent connect cluster resume <connector-id>
```

### Split-Brain Scenario

**Symptoms:**
- RAC nodes can't communicate with each other
- Services running on both nodes independently

**Cause**: Network partition between RAC nodes (cluster interconnect failure)

**Solution:**

This is a critical RAC issue requiring DBA intervention:

```sql
-- Check cluster health
SELECT inst_id, instance_name, status FROM gv$instance;

-- Check voting disk access
SELECT name, state FROM v$asm_disk WHERE group_number=0;

-- This requires immediate attention from Oracle DBA
-- May need to restart CRS/Grid Infrastructure
```

---

## JDBC Connector Specific Issues

### Error: "No suitable driver found"

**Symptoms:**
- Connector config validation fails
- Error about JDBC driver

**Cause**: Connector doesn't have Oracle JDBC driver (shouldn't happen with managed connector)

**Solution:**

For fully managed Confluent Cloud connectors, this is handled automatically. If using self-managed:

```bash
# Download Oracle JDBC driver
wget https://download.oracle.com/otn-pub/otn_software/jdbc/ojdbc8.jar

# Place in connector plugin path
```

### Connector Extremely Slow

**Symptoms:**
- Very slow data ingestion
- High latency

**Causes:**
1. Large table without proper indexing
2. Single task connector
3. Network latency
4. Inefficient query

**Solutions:**

1. **Increase connector tasks:**
```json
{
  "tasks.max": "3"
}
```

2. **Add index on incrementing column:**
```sql
CREATE INDEX idx_<table>_<id_column> ON <schema>.<table>(<id_column>);
```

3. **Use more efficient mode:**
```json
{
  "mode": "timestamp+incrementing",
  "timestamp.column.name": "updated_at",
  "incrementing.column.name": "id"
}
```

---

## XStream Specific Issues

### Error: "XStream is not configured"

**Symptoms:**
- XStream connector fails to start
- Error about XStream not being set up

**Cause**: XStream not configured on Oracle database

**Solution:**

See [XSTREAM-SETUP.md](./XSTREAM-SETUP.md) for complete setup, or quick check:

```sql
-- Check if XStream is configured
SELECT * FROM DBA_XSTREAM_OUTBOUND;

-- If empty, XStream needs to be configured
-- Requires DBA privileges and XStream license
```

### XStream Falling Behind

**Symptoms:**
- Lag between database changes and Kafka messages
- XStream apply lag increasing

**Cause**: High transaction volume or insufficient XStream resources

**Solution:**

```sql
-- Check XStream performance
SELECT apply_name, state, total_messages_applied, 
       total_messages_captured, total_latency
FROM DBA_XSTREAM_OUTBOUND_PROGRESS;

-- Increase parallelism
BEGIN
  DBMS_XSTREAM_ADM.ALTER_OUTBOUND(
    server_name => '<xstream_server_name>',
    parallelism => 4
  );
END;
/
```

---

## Network Connectivity Issues

### VPN/ExpressRoute/FastConnect Down

**Symptoms:**
- Sudden complete connectivity loss
- Was working, now all connections fail

**Cause**: Network link between Azure and RAC location is down

**Solutions:**

1. **Check Azure ExpressRoute:**
```bash
az network express-route show \
  --name <circuit-name> \
  --resource-group <rg>

# CircuitProvisioningState should be "Enabled"
# ServiceProviderProvisioningState should be "Provisioned"
```

2. **Check OCI FastConnect (if using OCI):**
```bash
oci network virtual-circuit get --virtual-circuit-id <id>

# lifecycleState should be "PROVISIONED"
```

3. **Test basic connectivity:**
```bash
# From Azure VM
ping <rac-node-ip>
traceroute <rac-node-ip>
```

4. **Contact network team** if links are down

---

## Debugging Commands

### Check RAC Cluster Status

```sql
-- Cluster-wide instance status
SELECT inst_id, instance_name, host_name, status, database_status
FROM gv$instance
ORDER BY inst_id;

-- Services across all instances
SELECT inst_id, name, enabled
FROM gv$services
WHERE name NOT LIKE 'SYS%'
ORDER BY name, inst_id;
```

### Check Listener Services

```bash
# On each RAC node
lsnrctl services LISTENER

# Should show services for all RAC instances
```

### Check ASM Status

```bash
# If using ASM for storage
srvctl status asm -detail

# Or from SQL
sqlplus / as sysasm
SELECT name, state FROM v$asm_diskgroup;
```

### Monitor Active Connections

```sql
-- See which nodes are handling connections
SELECT inst_id, username, machine, program, status
FROM gv$session
WHERE username IS NOT NULL
ORDER BY inst_id, username;
```

### AppGW Backend Health

```bash
# Detailed health status
az network application-gateway show-backend-health \
  --name <appgw-name> \
  --resource-group <rg> \
  -o json | jq '.backendAddressPools[0].backendHttpSettingsCollection[0].servers'
```

---

## Getting Help

If you're still experiencing issues:

1. **Collect diagnostics:**
   - Connector status and logs
   - `lsnrctl services` output from all nodes
   - `gv$instance` query results
   - AppGW backend health status
   - Network connectivity tests

2. **Check documentation:**
   - [QUICKSTART.md](./QUICKSTART.md)
   - [HA-TESTING.md](./HA-TESTING.md)
   - [APPGW-SETUP.md](./APPGW-SETUP.md)

3. **Oracle resources:**
   - Check `alert_<SID>.log` on each RAC node
   - Review `listener.log`
   - Check Grid Infrastructure logs in `$GRID_HOME/log`

4. **Open GitHub issue** with diagnostics

---

## Related Documentation

- [../README.md](../README.md) - Pattern overview
- [QUICKSTART.md](./QUICKSTART.md) - Deployment guide
- [HA-TESTING.md](./HA-TESTING.md) - High availability testing
- [APPGW-SETUP.md](./APPGW-SETUP.md) - Application Gateway configuration
