# Oracle RAC + Confluent Cloud via AppGW - Quick Start

Connect Confluent Cloud JDBC Source Connector to Oracle RAC through Azure Application Gateway.

## Architecture

```
Confluent Cloud → EAP → AppGW → [Network] → Oracle RAC Nodes
                        ↓
                  Bypasses SCAN VIPs
                  Direct to Node IPs
```

**Note:** Assumes network connectivity exists between AppGW and Oracle RAC (VPN, Direct Connect, etc.)

## Prerequisites

- Oracle RAC cluster (any location: OCI, on-premises, etc.)
- Network connectivity from Azure AppGW to Oracle RAC nodes (port 1521)
- Application Gateway (existing or new)
- Confluent Cloud with EAP provisioned

---

## Configuration Steps

### 1. Oracle RAC - Configure REMOTE_LISTENER (5 min)

**Critical**: Must be FQDN, not IPs.

```sql
-- On each RAC node
ALTER SYSTEM SET REMOTE_LISTENER='racnode-scan.<your-domain>:1521' SCOPE=BOTH;
ALTER SYSTEM REGISTER;

-- Verify
SELECT name, value FROM v$parameter WHERE name = 'remote_listener';
-- Should show FQDN, not IPs
```

### 2. Oracle RAC - Create Database User (5 min)

```sql
ALTER SESSION SET CONTAINER = <pdb_name>;

CREATE USER jdbc_connector IDENTIFIED BY "<password>";
GRANT CREATE SESSION TO jdbc_connector;
GRANT SELECT ON <schema>.<table> TO jdbc_connector;
```

### 3. Azure AppGW - Configure Backend Pool (10 min)

Get RAC node **private IPs** (not SCAN VIPs):

```bash
# Example: 10.99.1.108, 10.99.1.29
```

Add backend pool to AppGW:

```bash
az network application-gateway address-pool create \
  --gateway-name <appgw-name> \
  --resource-group <rg-name> \
  --name oracle_rac_oci \
  --servers 10.99.1.108 10.99.1.29
```

### 4. Azure AppGW - Configure Listener & Routing (10 min)

```bash
# Backend settings (use least connections for best load balancing)
az network application-gateway settings create \
  --gateway-name <appgw-name> \
  --resource-group <rg-name> \
  --name oracle_1521 \
  --port 1521 \
  --protocol Tcp \
  --timeout 60

# TCP listener
az network application-gateway listener create \
  --gateway-name <appgw-name> \
  --resource-group <rg-name> \
  --name oracle_listener \
  --frontend-port port_1521 \
  --frontend-ip appGwPrivateFrontendIpIPv4

# Routing rule
az network application-gateway rule create \
  --gateway-name <appgw-name> \
  --resource-group <rg-name> \
  --name route-to-oracle-rac \
  --listener oracle_listener \
  --address-pool oracle_rac_oci \
  --settings oracle_1521 \
  --priority 110
```

### 5. Verify AppGW Health (2 min)

```bash
az network application-gateway show-backend-health \
  --name <appgw-name> \
  --resource-group <rg-name>

# Both RAC nodes should show "Healthy"
```

### 6. Confluent Cloud - Configure DNS Wildcard (5 min)

In Confluent Cloud Console → Environment → Network → DNS:

- **Hostname pattern**: `*.<your-oracle-domain>`
- **Example**: `*.petertestnodes.peterglab.oraclevcn.com`
- **Target**: EAP endpoint or AppGW IP (via EAP)

**Why**: Catches all Oracle hostname references and routes through AppGW.

### 7. Deploy JDBC Source Connector (5 min)

Create `oracle-connector.json`:

```json
{
  "name": "oracle-rac-jdbc-source",
  "config": {
    "connector.class": "OracleDatabaseSource",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "<your-api-key>",
    "kafka.api.secret": "<your-api-secret>",
    "tasks.max": "1",
    
    "connection.host": "racnode-scan.<your-domain>",
    "connection.port": "1521",
    "connection.user": "jdbc_connector",
    "connection.password": "<password>",
    "db.name": "<pdb_name>.<domain>",
    
    "table.include.list": "<SCHEMA>.<TABLE>",
    "mode": "timestamp+incrementing",
    "incrementing.column.mapping": "<SCHEMA>.<TABLE>:[<ID_COL>]",
    "timestamp.columns.mapping": "<SCHEMA>.<TABLE>:[<TS_COL>]",
    
    "poll.interval.ms": "5000",
    "batch.max.rows": "100",
    "topic.prefix": "oracle-rac-",
    "output.data.format": "JSON"
  }
}
```

Deploy:

```bash
confluent environment use <env-id>
confluent kafka cluster use <cluster-id>
confluent connect cluster create --config-file oracle-connector.json
```

### 8. Verify Data Flow (2 min)

```bash
# Check connector status
confluent connect cluster list

# Should show RUNNING

# Verify topic created
confluent kafka topic list | grep oracle-rac

# Test: Insert data in Oracle
# INSERT INTO <schema>.<table> VALUES (...);
# COMMIT;

# Check message arrives (within 5 seconds)
confluent kafka topic consume oracle-rac-<SCHEMA>.<TABLE> --from-beginning
```

---

## Quick Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| "Oracle Database server is unreachable" | Network connectivity | Check network connectivity, AppGW health, firewall rules |
| "Got minus one from a read call" | REMOTE_LISTENER is IP not FQDN | `ALTER SYSTEM SET REMOTE_LISTENER='<scan-fqdn>:1521'` |
| "Unknown host specified" | Missing DNS wildcard | Add `*.<domain>` wildcard in Confluent Cloud |
| Backend "Unhealthy" | Firewall/routing issue | Check firewall allows TCP 1521 from AppGW subnet |
| Connector RUNNING but no data | Column mapping wrong | Verify incrementing/timestamp columns exist and have correct format |

---

## Key Points

✅ **REMOTE_LISTENER must be FQDN** - Critical for proper hostname routing  
✅ **AppGW backend = Node IPs** - NOT SCAN VIPs (10.99.1.x, not SCAN VIP addresses)  
✅ **DNS wildcard required** - Routes all Oracle hostnames through AppGW  
✅ **SCAN bypassed** - Direct node connections, AppGW provides load balancing  
✅ **Use least connections** - Better for long-lived JDBC connections  

---

## Total Setup Time: ~40 minutes

For detailed explanations and advanced configuration, see [ORACLE-RAC-APPGW-SETUP.md](./ORACLE-RAC-APPGW-SETUP.md)
