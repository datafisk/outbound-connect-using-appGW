# Connecting Confluent Cloud to Oracle RAC via Azure Application Gateway

This guide explains how to configure Azure Application Gateway (AppGW) with Confluent Cloud Egress Access Point (EAP) to enable connectivity to Oracle Real Application Clusters (RAC) for JDBC Source Connector.

## Architecture Overview

```
Confluent Cloud Connector
    ↓
Egress Access Point (EAP) - Azure Private Network Interface
    ↓
Azure Application Gateway (TCP Listener on port 1521)
    ↓
[Network Connectivity - VPN, Direct Connect, etc.]
    ↓
Oracle RAC Nodes (Direct to Node IPs, bypassing SCAN VIPs)
```

**Note:** This guide assumes network connectivity exists between the Azure Application Gateway subnet and Oracle RAC nodes. The connectivity method (VPN, ExpressRoute, Direct Connect, etc.) is environment-specific and outside the scope of this guide.

### Key Architectural Points

1. **SCAN Bypass**: The AppGW backend pool uses **node IPs**, not SCAN VIPs, because:
   - SCAN VIP redirects use unroutable addresses from Confluent Cloud
   - AppGW is Layer 4 (TCP) and cannot understand Oracle TNS protocol
   - AppGW cannot intercept and rewrite TNS redirects

2. **Load Balancing**: 
   - Oracle RAC's intelligent SCAN-based load balancing is bypassed
   - AppGW provides basic TCP load balancing (round-robin or least connections)
   - Adequate for Kafka connector use cases

3. **DNS Wildcard**: 
   - Required to catch any Oracle hostname redirects
   - Routes all Oracle FQDNs back through AppGW

---

## Prerequisites

### Existing Infrastructure

- **Oracle RAC Cluster**: 
  - Oracle Database 19c or later
  - 2+ node RAC cluster deployed (any platform: OCI, on-premises, etc.)
  - SCAN configured with FQDNs
  - Network connectivity between nodes

- **Azure Infrastructure**:
  - Azure VNet with sufficient address space
  - Existing Application Gateway (or create new one)
  - **Network connectivity from AppGW subnet to Oracle RAC nodes**
    - Can be VPN, ExpressRoute, Direct Connect, etc.
    - TCP port 1521 must be allowed
  
- **Confluent Cloud**:
  - Environment and Kafka cluster created
  - Egress Access Point (EAP) provisioned in Azure region
  - VNet peering between Confluent Cloud and your Azure VNet

---

## Step 1: Oracle RAC Configuration

### 1.1 Configure REMOTE_LISTENER with FQDN

This is **critical** - REMOTE_LISTENER must use FQDN format, not IPs.

Connect to each RAC node and run:

```sql
-- Check current configuration
SELECT name, value FROM v$parameter 
WHERE name IN ('local_listener', 'remote_listener', 'db_domain');

-- Set REMOTE_LISTENER to SCAN FQDN
ALTER SYSTEM SET REMOTE_LISTENER='<scan-name>.<domain>:1521' SCOPE=BOTH;

-- Example:
ALTER SYSTEM SET REMOTE_LISTENER='racnode-scan.petertestnodes.peterglab.oraclevcn.com:1521' SCOPE=BOTH;

-- Register with listener
ALTER SYSTEM REGISTER;
```

**Why FQDN is required**: When using FQDN for REMOTE_LISTENER, Oracle maintains FQDN-based service registration. Combined with the Confluent Cloud DNS wildcard, this ensures all hostname references route back through AppGW.

### 1.2 Configure LOCAL_LISTENER (Optional)

LOCAL_LISTENER can be either FQDN or IP since we bypass SCAN redirects:

```sql
-- Node 1 - Option A: Use FQDN
ALTER SYSTEM SET LOCAL_LISTENER='(ADDRESS=(PROTOCOL=TCP)(HOST=racnode1.<domain>)(PORT=1521))' SCOPE=BOTH SID='<instance1_name>';

-- Node 1 - Option B: Use IP (works because we bypass SCAN)
ALTER SYSTEM SET LOCAL_LISTENER='(ADDRESS=(PROTOCOL=TCP)(HOST=<node1_ip>)(PORT=1521))' SCOPE=BOTH SID='<instance1_name>';

-- Repeat for Node 2 with appropriate values
ALTER SYSTEM REGISTER;
```

### 1.3 Create Database User for Connector

```sql
-- Connect to PDB
ALTER SESSION SET CONTAINER = <pdb_name>;

-- Create user
CREATE USER jdbc_connector IDENTIFIED BY "<secure_password>";

-- Grant required privileges
GRANT CREATE SESSION TO jdbc_connector;
GRANT SELECT ON DBA_TABLES TO jdbc_connector;
GRANT SELECT ON DBA_TAB_COLUMNS TO jdbc_connector;
GRANT SELECT ON ALL_TABLES TO jdbc_connector;
GRANT SELECT ON ALL_TAB_COLUMNS TO jdbc_connector;

-- Grant SELECT on source tables (example)
GRANT SELECT ON <schema>.<table> TO jdbc_connector;
```

### 1.4 Verify Oracle Configuration

```sql
-- Check listener configuration
SELECT name, value FROM v$parameter 
WHERE name IN ('local_listener', 'remote_listener');

-- Verify service registration (from grid user)
lsnrctl services LISTENER_SCAN1

-- Should show services registered with addresses
```

---

## Step 2: Azure Application Gateway Configuration

### 2.1 Get RAC Node Private IPs

Determine the **private IP addresses** of your RAC nodes (not SCAN VIPs):

```bash
# From OCI Console or CLI
oci compute instance list-vnics --instance-id <instance_ocid> \
  --query 'data[0]."private-ip"'

# Example output:
# Node 1: 10.99.1.108
# Node 2: 10.99.1.29
```

### 2.2 Configure AppGW Backend Pool

Add a backend address pool with RAC node IPs:

```hcl
# Terraform example
resource "azurerm_application_gateway" "example" {
  # ... existing configuration ...

  # Backend pool with RAC node IPs (NOT SCAN VIPs)
  backend_address_pool {
    name         = "oracle_rac_oci"
    ip_addresses = ["10.99.1.108", "10.99.1.29"]  # Node private IPs
  }

  # Backend settings for Oracle TCP port 1521
  backend_settings {
    name     = "oracle_1521"
    port     = 1521
    protocol = "Tcp"
    timeout  = 60  # Increased timeout for database connections
  }

  # TCP Listener on port 1521
  listener {
    name                           = "oracle_listener"
    frontend_ip_configuration_name = "appGwPrivateFrontendIpIPv4"
    frontend_port_name             = "port_1521"
    protocol                       = "Tcp"
  }

  # Frontend port
  frontend_port {
    name = "port_1521"
    port = 1521
  }

  # Routing rule
  routing_rule {
    name                      = "route-to-oracle-rac"
    rule_type                 = "Basic"
    listener_name             = "oracle_listener"
    backend_address_pool_name = "oracle_rac_oci"
    backend_settings_name     = "oracle_1521"
    priority                  = 110
  }

  # Health probe for Oracle
  probe {
    name                = "oracle_rac_probe"
    protocol            = "Tcp"
    port                = 1521
    interval            = 30
    timeout             = 60
    unhealthy_threshold = 3
  }
}
```

**Azure CLI Alternative:**

```bash
# Add backend pool
az network application-gateway address-pool create \
  --gateway-name <appgw-name> \
  --resource-group <rg-name> \
  --name oracle_rac_oci \
  --servers 10.99.1.108 10.99.1.29

# Add backend settings
az network application-gateway settings create \
  --gateway-name <appgw-name> \
  --resource-group <rg-name> \
  --name oracle_1521 \
  --port 1521 \
  --protocol Tcp \
  --timeout 60

# Add TCP listener
az network application-gateway listener create \
  --gateway-name <appgw-name> \
  --resource-group <rg-name> \
  --name oracle_listener \
  --frontend-port port_1521 \
  --frontend-ip appGwPrivateFrontendIpIPv4

# Add routing rule
az network application-gateway rule create \
  --gateway-name <appgw-name> \
  --resource-group <rg-name> \
  --name route-to-oracle-rac \
  --listener oracle_listener \
  --address-pool oracle_rac_oci \
  --settings oracle_1521 \
  --priority 110
```

### 2.3 Verify AppGW Health

```bash
# Check backend health (may take 2-3 minutes)
az network application-gateway show-backend-health \
  --name <appgw-name> \
  --resource-group <rg-name> \
  --query 'backendAddressPools[?backendAddressPool.name==`oracle_rac_oci`]'

# Both backends should show "Healthy"
```

---

## Step 3: Confluent Cloud Configuration

### 3.1 Configure DNS Wildcard in Confluent Cloud

**Critical**: Configure a wildcard DNS entry that resolves ALL Oracle hostnames to the AppGW.

In Confluent Cloud Console:
1. Navigate to your Environment → Network → DNS
2. Add DNS entry:
   - **Hostname pattern**: `*.petertestnodes.peterglab.oraclevcn.com` (your Oracle domain)
   - **Target**: EAP endpoint or AppGW private IP accessible via EAP
   - **TTL**: 60 seconds

**Why wildcard is required**: 
- Oracle uses multiple FQDNs (SCAN name, node names, service names)
- Wildcard catches all Oracle hostname references
- Routes everything back through AppGW

### 3.2 Verify DNS Resolution

From Confluent Cloud side (if you have access to test):
```bash
# Should resolve to EAP/AppGW IP
nslookup racnode-scan.petertestnodes.peterglab.oraclevcn.com
nslookup racnode1.petertestnodes.peterglab.oraclevcn.com
```

---

## Step 4: Create Oracle JDBC Source Connector

### 4.1 Connector Configuration

Create `oracle-rac-connector.json`:

```json
{
  "name": "oracle-rac-jdbc-source",
  "config": {
    "connector.class": "OracleDatabaseSource",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "<your-kafka-api-key>",
    "kafka.api.secret": "<your-kafka-api-secret>",
    "tasks.max": "1",
    
    "connection.host": "racnode-scan.petertestnodes.peterglab.oraclevcn.com",
    "connection.port": "1521",
    "connection.user": "jdbc_connector",
    "connection.password": "<jdbc_connector_password>",
    "db.name": "<pdb_name>.<domain>",
    "oracle.net.ssl_server_dn_match": "false",
    
    "table.include.list": "<SCHEMA>.<TABLE>",
    "mode": "timestamp+incrementing",
    "incrementing.column.mapping": "<SCHEMA>.<TABLE>:[<ID_COLUMN>]",
    "timestamp.columns.mapping": "<SCHEMA>.<TABLE>:[<TIMESTAMP_COLUMN>]",
    
    "poll.interval.ms": "5000",
    "batch.max.rows": "100",
    
    "topic.prefix": "oracle-rac-",
    "output.data.format": "JSON",
    "output.key.format": "JSON"
  }
}
```

### 4.2 Deploy Connector

```bash
# Set environment and cluster
confluent environment use <env-id>
confluent kafka cluster use <cluster-id>

# Create connector
confluent connect cluster create --config-file oracle-rac-connector.json

# Check status
confluent connect cluster list
confluent connect cluster describe <connector-id>
```

### 4.3 Verify Data Flow

```bash
# List topics (should see oracle-rac-<schema>.<table>)
confluent kafka topic list | grep oracle-rac

# Consume sample messages
confluent kafka topic consume oracle-rac-<SCHEMA>.<TABLE> --from-beginning

# Insert test data in Oracle
# INSERT INTO <schema>.<table> VALUES (...);
# COMMIT;

# Verify message appears in topic within poll.interval.ms
```

---

## Architecture Deep Dive

### Why We Bypass SCAN

**Problem with using SCAN VIPs:**
```
Connector → SCAN VIP (10.99.1.239)
         → SCAN listener redirects to LOCAL_LISTENER (10.99.1.108)
         → Connector cannot route to 10.99.1.108 from Confluent Cloud
         → Connection fails: "Got minus one from a read call"
```

**Solution - Direct to Node Listeners:**
```
Connector → SCAN FQDN (DNS wildcard) → AppGW
         → AppGW backend pool → Node IP (10.99.1.108 or .29)
         → Direct connection to node listener
         → NO TNS redirect, LOCAL_LISTENER never used
         → Connection succeeds
```

### Load Balancing Comparison

| Feature | Oracle RAC SCAN | AppGW Solution |
|---------|-----------------|----------------|
| Protocol awareness | TNS protocol aware | Layer 4 TCP only |
| Load metric | Instance load, connections, CPU | Round-robin or least connections |
| Service-based routing | Yes | No |
| Failover | Automatic redirect | Health probe based |
| Client impact | TNS redirect (2 connections) | Single connection |
| Complexity | High | Low |
| **For Kafka Connector** | **Not achievable** | **Sufficient** |

### Why REMOTE_LISTENER Format Matters

Even though we bypass SCAN VIPs, **REMOTE_LISTENER must be FQDN**:

1. Instances register services with SCAN using REMOTE_LISTENER
2. FQDN format ensures service registration maintains hostname-based addressing
3. Combined with DNS wildcard, any hostname Oracle references routes back through AppGW
4. IP-based REMOTE_LISTENER can cause Oracle to use IP addresses in service advertisements
5. Those IPs aren't routable from Confluent Cloud

**Bottom line**: `REMOTE_LISTENER = FQDN` is required, even though we bypass SCAN.

---

## Troubleshooting

### Connector Status: FAILED - "Oracle Database server is unreachable"

**Check:**
1. Network connectivity between AppGW and Oracle RAC nodes
2. AppGW backend health (both nodes should be Healthy)
3. Firewall rules allow TCP 1521 from AppGW subnet to Oracle RAC nodes
4. AppGW subnet can route to Oracle RAC network

**Test connectivity from Azure VM:**
```bash
# From Azure VM in same VNet as AppGW
nc -zv <oracle-node1-ip> 1521
nc -zv <oracle-node2-ip> 1521

# Should show "succeeded" or "open"
```

### Connector Status: FAILED - "Got minus one from a read call"

**Cause**: Oracle TNS redirect to unroutable IP address

**Check:**
```sql
-- Verify REMOTE_LISTENER is FQDN, not IP
SELECT name, value FROM v$parameter WHERE name = 'remote_listener';

-- Should show FQDN like:
-- racnode-scan.petertestnodes.peterglab.oraclevcn.com:1521

-- NOT IPs like:
-- 10.99.1.239:1521,10.99.1.220:1521
```

**Fix:**
```sql
ALTER SYSTEM SET REMOTE_LISTENER='<scan-fqdn>:1521' SCOPE=BOTH;
ALTER SYSTEM REGISTER;
```

Then restart the connector.

### Connector Status: FAILED - "Unknown host specified"

**Cause**: DNS wildcard not configured in Confluent Cloud

**Check:**
1. Confluent Cloud DNS has wildcard entry: `*.<oracle-domain>`
2. Wildcard resolves to EAP or AppGW (via EAP)
3. Domain matches Oracle db_domain parameter

### AppGW Backend Shows "Unhealthy"

**Check:**
1. Network connectivity from AppGW to Oracle RAC nodes
2. Firewall rules allow TCP 1521 from AppGW subnet
3. Oracle listener is running on the node
4. Oracle RAC nodes are up and accessible

**Verify:**
```bash
# From RAC node, check listener status
lsnrctl status

# Should show:
# The listener supports no services
# OR list of registered services
```

### Messages Not Flowing (Connector shows RUNNING)

**Check:**
1. Table has incrementing/timestamp columns configured correctly
2. User has SELECT privileges on the table
3. Check connector logs for errors

**Test:**
```sql
-- Insert test record
INSERT INTO <schema>.<table> VALUES (...);
COMMIT;

-- Wait poll.interval.ms (default 5000ms = 5 seconds)
-- Check topic for new message
```

### Connection Works but Data Duplicates

**Issue**: Records repeat every poll interval (like CANARY_TEST_MESSAGE repeating)

**Cause**: Incrementing or timestamp column not configured correctly

**Check:**
```json
{
  "mode": "timestamp+incrementing",
  "incrementing.column.mapping": "SCHEMA.TABLE:[ID_COLUMN]",  // Must be unique, increasing
  "timestamp.columns.mapping": "SCHEMA.TABLE:[UPDATED_AT]"    // Must update on every change
}
```

Verify column data types:
- Incrementing column: NUMBER, INT (auto-incrementing)
- Timestamp column: TIMESTAMP, DATE (automatically updated)

---

## Performance Tuning

### Connector Performance

```json
{
  "tasks.max": "1",           // Start with 1, increase if needed
  "poll.interval.ms": "5000", // Decrease for lower latency, increase for lower DB load
  "batch.max.rows": "500",    // Increase for higher throughput
  "numeric.mapping": "best_fit" // For better number handling
}
```

### AppGW Timeout

Increase timeout for long-running queries:

```hcl
backend_settings {
  name     = "oracle_1521"
  port     = 1521
  protocol = "Tcp"
  timeout  = 120  # Increase to 120 seconds if queries are slow
}
```

### Oracle Connection Pool

For multiple connectors, ensure Oracle has sufficient connections:

```sql
-- Check current connections
SELECT username, count(*) 
FROM v$session 
WHERE username = 'JDBC_CONNECTOR' 
GROUP BY username;

-- Increase processes if needed
ALTER SYSTEM SET processes=500 SCOPE=SPFILE;
-- Requires restart
```

---

## Security Considerations

1. **Credentials Management**:
   - Use Confluent Cloud Secrets for API keys
   - Rotate Oracle passwords regularly
   - Use least-privilege database user

2. **Network Security**:
   - Keep firewall rules restrictive (only port 1521 from AppGW subnet)
   - Use private IPs only (no public endpoints)
   - Monitor network connectivity health

3. **SSL/TLS** (Optional):
   - Configure Oracle for SSL connections
   - Update connector config with SSL settings
   - Requires Oracle Wallet configuration

4. **Monitoring**:
   - Monitor connector status and lag
   - Set up alerts for connector failures
   - Monitor AppGW backend health
   - Track Oracle database load from connector queries

---

## Summary

This architecture enables Confluent Cloud to connect to Oracle RAC via:

✅ **Azure Application Gateway** - TCP load balancing to RAC nodes  
✅ **Network Connectivity** - Private connectivity from AppGW to Oracle RAC  
✅ **DNS Wildcard** - Routes all Oracle hostnames through AppGW  
✅ **SCAN Bypass** - Direct node connections (no TNS redirects)  

**Key Configuration Requirements:**
- REMOTE_LISTENER = FQDN (not IPs)
- AppGW backend pool = Node IPs (not SCAN VIPs)
- Confluent Cloud DNS wildcard = `*.<oracle-domain>`

**Trade-offs:**
- Lose Oracle RAC intelligent load balancing
- Gain Confluent Cloud connectivity with AppGW basic load balancing
- Adequate for Kafka connector use cases

---

## References

- [Confluent Oracle Database Source Connector](https://docs.confluent.io/cloud/current/connectors/cc-oracle-db-source.html)
- [Azure Application Gateway TCP Support](https://learn.microsoft.com/en-us/azure/application-gateway/overview-v2)
- [Oracle RAC SCAN Configuration](https://docs.oracle.com/en/database/oracle/oracle-database/19/racad/understanding-the-single-client-access-name.html)
- [Confluent Cloud Egress Access Points](https://docs.confluent.io/cloud/current/networking/private-links/aws-privatelink-egress.html)
