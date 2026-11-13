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
Oracle RAC Nodes (direct to the node VIPs, bypassing the SCAN listener)
```

**Note:** This guide assumes network connectivity exists between the Azure Application Gateway subnet and Oracle RAC nodes. The connectivity method (VPN, ExpressRoute, Direct Connect, etc.) is environment-specific and outside the scope of this guide.

### Key Architectural Points

1. **SCAN Bypass**: The AppGW backend pool uses the **node VIPs**, not the SCAN addresses, because:
   - The SCAN listener answers a connect with a TNS redirect to a node listener address (the VIP endpoint from `LOCAL_LISTENER`), and the client reconnects there
   - From Confluent Cloud that address (a private VIP or an Oracle-internal hostname) is not resolvable or routable
   - AppGW is Layer 4 (TCP) and cannot understand Oracle TNS, so it cannot intercept or rewrite the redirect
   - Pointing the connector's hostname at the AppGW and forwarding to a node listener avoids the redirect: the SCAN listener is never contacted

2. **Load Balancing**: 
   - Oracle RAC's service-aware SCAN load balancing is bypassed
   - AppGW distributes new TCP connections across healthy backends and cannot tell whether a node carries the service
   - The database service must therefore be registered on **every** node in the pool

3. **DNS entry**: 
   - The hostname used in `connection.host` must resolve, in Confluent Cloud egress DNS, to the EAP that fronts the AppGW
   - A wildcard for the Oracle domain is optional and only a safety net for other names a client might be handed

---

## Prerequisites

### Existing Infrastructure

- **Oracle RAC Cluster**: 
  - Oracle Database 19c or later
  - 2+ node RAC cluster deployed (any platform: OCI, on-premises, etc.)
  - SCAN configured (it stays in place, but the connector does not use it)
  - Database service running on every node
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

### 1.1 Check the listener configuration (no change needed)

Leave `REMOTE_LISTENER` and `LOCAL_LISTENER` at their defaults.

```sql
SELECT inst_id, name, value FROM gv$parameter
WHERE name IN ('local_listener', 'remote_listener', 'db_domain');
```

- `LOCAL_LISTENER` is the node VIP endpoint. By default the node listener binds the VIP, which is why the AppGW pool uses the VIPs.
- `REMOTE_LISTENER` (normally `<scan-name>:1521`) only controls where instances register with the SCAN listeners. It is not in the connector's path.

Earlier versions of this guide said `REMOTE_LISTENER` must be an FQDN. That was never verified and is not a requirement.

### 1.2 Verify the service is registered on every node

The AppGW cannot route by service, so every node in the pool must carry the service the connector uses:

```sql
SELECT inst_id, name FROM gv$active_services WHERE name NOT LIKE 'SYS%';
```

```bash
# As the grid user, on each node
lsnrctl services
srvctl status service -d <db_unique_name>
```

If a service runs on only one node, either make it uniform (run on all instances) or put only that node's VIP in the pool. See [SINGLE-INSTANCE-FINDINGS.md](./SINGLE-INSTANCE-FINDINGS.md).

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
SELECT inst_id, name, value FROM gv$parameter
WHERE name IN ('local_listener', 'remote_listener');

-- Verify service registration on each node listener (from grid user, on each node)
-- lsnrctl services
-- Should list the connector's service with an instance on every node
```

---

## Step 2: Azure Application Gateway Configuration

### 2.1 Get the RAC Node VIPs

Determine the **VIP addresses** of your RAC nodes. Not the SCAN addresses, and not the nodes' physical IPs:

```bash
# As the grid user on a RAC node
srvctl config vip -node <node1>
srvctl config vip -node <node2>

# On an OCI DB system the VIPs are also shown in the console under the DB system's nodes.
# Example output:
# Node 1 VIP: <node1-vip>
# Node 2 VIP: <node2-vip>
```

### 2.2 Configure AppGW Backend Pool

Add a backend address pool with the RAC node VIPs:

```hcl
# Terraform example (checked with terraform plan on azurerm 5.13.0, not applied: the `backend`, `listener` and `routing_rule`
# blocks support Tcp and Tls; the older http_listener / backend_http_settings /
# request_routing_rule blocks are HTTP only)
resource "azurerm_application_gateway" "example" {
  # ... existing configuration ...

  # Backend pool with the RAC node VIPs (NOT the SCAN addresses)
  backend_address_pool {
    name         = "oracle_rac_oci"
    ip_addresses = ["<node1-vip>", "<node2-vip>"]  # Node VIPs
  }

  # Backend settings for Oracle TCP port 1521
  backend {
    name               = "oracle_1521"
    port               = 1521
    protocol           = "Tcp"
    timeout_in_seconds = 900  # Idle timeout: long-lived database connections
    probe_name         = "oracle_rac_probe"
  }

  # Frontend port
  frontend_port {
    name = "port_1521"
    port = 1521
  }

  # TCP listener on the private frontend
  listener {
    name                           = "oracle_listener"
    frontend_ip_configuration_name = "appGwPrivateFrontendIpIPv4"
    frontend_port_name             = "port_1521"
    protocol                       = "Tcp"
  }

  # Routing rule
  routing_rule {
    name                      = "route-to-oracle-rac"
    listener_name             = "oracle_listener"
    backend_address_pool_name = "oracle_rac_oci"
    backend_name              = "oracle_1521"
    priority                  = 110
  }

  # TCP health probe (a connect test only: it cannot see whether the database
  # service exists on the node, see the troubleshooting guide)
  probe {
    name                = "oracle_rac_probe"
    protocol            = "Tcp"
    port                = 1521
    interval            = 30
    timeout             = 30  # must not exceed interval
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
  --servers <node1-vip> <node2-vip>

# Add backend settings
az network application-gateway settings create \
  --gateway-name <appgw-name> \
  --resource-group <rg-name> \
  --name oracle_1521 \
  --port 1521 \
  --protocol Tcp \
  --timeout 900

# Add TCP listener
az network application-gateway listener create \
  --gateway-name <appgw-name> \
  --resource-group <rg-name> \
  --name oracle_listener \
  --frontend-port port_1521 \
  --frontend-ip appGwPrivateFrontendIpIPv4

# Add routing rule
az network application-gateway routing-rule create \
  --gateway-name <appgw-name> \
  --resource-group <rg-name> \
  --name route-to-oracle-rac \
  --listener oracle_listener \
  --address-pool oracle_rac_oci \
  --settings oracle_1521 \
  --priority 110
```

### 2.3 Verify the Route

`az network application-gateway show-backend-health` returns nothing for TCP pools, so test through the gateway from a VM that can reach its private frontend IP:

```bash
# Repeat several times; instance_name should alternate between the nodes
sqlplus <user>/<password>@//<appgw-private-ip>:1521/<service_name> <<< "SELECT instance_name FROM v\$instance;"
```

The AppGW's own TCP probe appears in each node's listener log as `ORA-12537` with `<unknown connect data>` about every 30 seconds. That is benign.

---

## Step 3: Confluent Cloud Configuration

### 3.1 Configure the Egress DNS Entry in Confluent Cloud

**Critical**: The hostname the connector connects to must resolve to the EAP that fronts the AppGW. The connector then never contacts a SCAN listener or a node directly.

In Confluent Cloud Console:
1. Navigate to your Environment → Network → DNS
2. Add a DNS entry:
   - **Domain**: the hostname you will use as `connection.host` (for example `oracle.<your-domain>`)
   - **Target**: the Egress Access Point that routes to the AppGW private frontend IP
   - **TTL**: 60 seconds

This hostname is only a label. It does not need to match the SCAN name or any node name, because the AppGW forwards to the VIPs whatever name was used.

**Optional wildcard**: a wildcard for your Oracle domain (`*.<oracle-domain>`) is only a safety net if a client is handed another Oracle hostname. In this pattern the connector is never redirected, so it is not required. Note that a name caught this way would also need a matching AppGW listener and pool to be useful.

### 3.2 Verify DNS Resolution

From the Confluent Cloud side (if you have access to test):
```bash
# Should resolve to the EAP / AppGW address
nslookup oracle.<your-domain>
```

### 3.3 TLS and Hostname Validation

**Recommendation: use a TCP listener (pass-through) on the AppGW, also when the Oracle listener uses TLS (TCPS).** The AppGW then only forwards bytes. It does not terminate, inspect or re-encrypt the TLS session, so the TLS stays end to end between the connector and the database, and the AppGW needs no certificate. Terminating TLS on the AppGW is **not covered by this repo**; use it only if you have a specific requirement for it, and test it yourself.

With plain TCP the egress DNS name is only a label. **With TCPS it matters:** the connector checks the certificate Oracle presents against the hostname it dialed (`connection.host`, the egress DNS name). Either:

- put the egress DNS name in the Oracle server certificate's SAN/CN (preferred), or
- disable hostname/DN validation on the connector (less secure: the connection is still encrypted, but the server's identity is no longer checked).

Notes:
- Disabling validation (for the JDBC connector, `oracle.net.ssl_server_dn_match=false`, as in the example in step 4.1) lets the connection through but no longer verifies the server's identity.
- Not tested in this repo: the OCI retest used a plain TCP listener, and the connector config had no TLS setting. Confirm the exact TLS and DN-match property names for your connector type (the XStream connector's differ from JDBC) before relying on them.
- Listeners sharing an AppGW port must all be the same type (TCP or TLS), so a TCP listener cannot be added on a port that already has a TLS listener.
- Typical failure: `SSLHandshakeException` / "certificate does not match" or `No subject alternative names matching ...` in the connector log.

---

## Step 4: Create Oracle JDBC Source Connector

### 4.1 Connector Configuration

Create `oracle-rac-connector.json` (a flat file, as `confluent connect cluster create --config-file` expects; `connection.host` is the egress DNS name from step 3.1):

```json
{
  "name": "oracle-rac-jdbc-source",
  "connector.class": "OracleDatabaseSource",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "<your-kafka-api-key>",
  "kafka.api.secret": "<your-kafka-api-secret>",
  "tasks.max": "1",
  "connection.host": "oracle.<your-domain>",
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

**Problem with using the SCAN name:**
```
Connector → SCAN name → SCAN listener (SCAN IP)
         → SCAN listener replies with a TNS REDIRECT to a node listener address
           (the VIP endpoint registered through LOCAL_LISTENER)
         → Connector opens a second connection to that address
         → Address is a private VIP or an Oracle-internal hostname: not resolvable
           or not routable from Confluent Cloud
         → Connection fails ("Got minus one from a read call", ORA-12537)
```

**Solution - direct to the node listeners via the AppGW:**
```
Connector → egress DNS name → EAP → AppGW (TCP listener)
         → AppGW backend pool → node VIP (<node1-vip> or <node2-vip>)
         → Node listener hands the session to a server process on that node
         → The SCAN listener is never contacted, so there is no redirect
```

The hostname in `connection.host` is only a label that DNS steers to the AppGW. The SCAN name is not involved.

### Load Balancing Comparison

| Feature | Oracle RAC SCAN | AppGW Solution |
|---------|-----------------|----------------|
| Protocol awareness | TNS protocol aware | Layer 4 TCP only |
| Load metric | Instance load, connections, CPU | New TCP connections across healthy backends |
| Service-based routing | Yes | No: the service must exist on every pooled node |
| Failover | Redirect to a node that has the service | TCP health probe removes an unreachable VIP; it cannot see `ORA-12514` |
| Client impact | TNS redirect (2 connections) | Single connection |
| Complexity | High | Low |
| **From Confluent Cloud** | **Not usable (redirect cannot be followed)** | **Works** |

### REMOTE_LISTENER and LOCAL_LISTENER

Neither needs to be changed:

- `REMOTE_LISTENER` (normally `<scan-name>:1521`) tells each instance which SCAN listeners to register its services with. It never appears in what a client is sent.
- `LOCAL_LISTENER` is the node VIP endpoint. It is what a SCAN redirect would hand to a client. By default the node listener binds the VIP, so the AppGW pool must contain the **VIPs**, not the physical IPs.

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

**Cause**: The connection was closed mid-handshake. Typical causes in this pattern:
- `connection.host` resolves to something other than the AppGW (for example the SCAN name resolves to a SCAN IP, so a TNS redirect is returned)
- The AppGW pool contains addresses with no listener (for example physical IPs instead of VIPs)
- The listener on the AppGW port is TLS while the connector speaks plain TCP, or the reverse

**Check:**
```bash
# From the connector's side: the name must resolve to the EAP / AppGW
nslookup oracle.<your-domain>

# From a VM in the AppGW's network: bypass Confluent and test the gateway and each VIP directly
sqlplus <user>/<password>@//<appgw-private-ip>:1521/<service_name>
sqlplus <user>/<password>@//<node1-vip>:1521/<service_name>
sqlplus <user>/<password>@//<node2-vip>:1521/<service_name>
```

**Fix**: Correct the egress DNS entry, use the VIPs in the pool, and make sure the AppGW listener is plain TCP. Then restart the connector.

### Connector Status: FAILED - "Unknown host specified"

**Cause**: The name in `connection.host` has no egress DNS entry in Confluent Cloud

**Check:**
1. Confluent Cloud egress DNS has an entry for exactly the hostname used in `connection.host`
2. The entry targets the EAP that routes to the AppGW
3. The hostname is spelled the same in the connector config and the DNS entry

### Connector Status: FAILED - TLS certificate / hostname mismatch

**Cause**: The Oracle listener uses TLS (TCPS) and the egress DNS name is not in Oracle's certificate, which the connector sees through the AppGW's TCP pass-through.

**Check:**
1. Is the Oracle listener TCPS, and is the AppGW listener a TCP (pass-through) listener?
2. Does the certificate's SAN/CN include the exact `connection.host` name?

**Fix**: Reissue the certificate with the egress DNS name, or disable hostname/DN validation on the connector (less secure). See step 3.3.

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
backend {
  name               = "oracle_1521"
  port               = 1521
  protocol           = "Tcp"
  timeout_in_seconds = 120  # Increase to 120 seconds if queries are slow
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
   - The egress DNS name must match the certificate the connector sees (or hostname validation must be disabled). See step 3.3

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
✅ **Egress DNS entry** - The connector's hostname resolves to the EAP in front of the AppGW  
✅ **SCAN Bypass** - Direct node connections (no TNS redirects)  

**Key Configuration Requirements:**
- AppGW backend pool = node VIPs (not the SCAN addresses, not physical IPs)
- AppGW listener = plain TCP (if Oracle uses TLS, the egress DNS name must match the certificate; see step 3.3)
- Database service registered on every node in the pool
- `REMOTE_LISTENER` and `LOCAL_LISTENER` left at their defaults

**Trade-offs:**
- Lose Oracle RAC's service-aware load balancing
- The AppGW's TCP probe cannot see `ORA-12514`
- XStream node-failure behaviour is in [HA-TESTING-XSTREAM.md](../../oracle-rac-xstream/docs/HA-TESTING-XSTREAM.md): data is not lost, but recovery after some failures is manual

---

## References

- [Confluent Oracle Database Source Connector](https://docs.confluent.io/cloud/current/connectors/cc-oracle-db-source.html)
- [Azure Application Gateway TCP Support](https://learn.microsoft.com/en-us/azure/application-gateway/overview-v2)
- [Oracle RAC SCAN Configuration](https://docs.oracle.com/en/database/oracle/oracle-database/19/racad/understanding-the-single-client-access-name.html)
- [Confluent Cloud Egress Access Points](https://docs.confluent.io/cloud/current/networking/private-links/aws-privatelink-egress.html)
