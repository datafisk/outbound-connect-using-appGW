# Oracle RAC + Confluent Cloud via AppGW - Quick Start

Connect Confluent Cloud JDBC Source Connector to Oracle RAC through Azure Application Gateway.

## Architecture

```
Confluent Cloud → EAP → AppGW → [Network] → Oracle RAC Nodes
                        ↓
                  Bypasses the SCAN listener
                  Direct to the node VIPs
```

**Note:** Assumes network connectivity exists between AppGW and Oracle RAC (VPN, Direct Connect, etc.)

## Prerequisites

- Oracle RAC cluster (any location: OCI, on-premises, etc.)
- Network connectivity from Azure AppGW to Oracle RAC nodes (port 1521)
- Application Gateway (existing or new)
- Confluent Cloud with EAP provisioned

---

## Configuration Steps

### 1. Oracle RAC - Check Listener and Service (5 min)

**Critical**: The connector's service must be registered on **every** node whose VIP goes in the AppGW pool. Leave `LOCAL_LISTENER` and `REMOTE_LISTENER` at their defaults.

```sql
SELECT inst_id, name, value FROM gv$parameter WHERE name IN ('local_listener','remote_listener');
SELECT inst_id, name FROM gv$active_services WHERE name NOT LIKE 'SYS%';
-- The service must appear for each instance
```

### 2. Oracle RAC - Create Database User (5 min)

```sql
ALTER SESSION SET CONTAINER = <pdb_name>;

CREATE USER jdbc_connector IDENTIFIED BY "<password>";
GRANT CREATE SESSION TO jdbc_connector;
GRANT SELECT ON <schema>.<table> TO jdbc_connector;
```

### 3. Azure AppGW - Configure Backend Pool (10 min)

Get the RAC node **VIPs** (not the SCAN addresses, not the physical IPs):

```bash
# As the grid user on a RAC node
srvctl config vip -node <node1>
srvctl config vip -node <node2>
# Example: <node1-vip>, <node2-vip>
```

Add backend pool to AppGW:

```bash
az network application-gateway address-pool create \
  --gateway-name <appgw-name> \
  --resource-group <rg-name> \
  --name oracle_rac_oci \
  --servers <node1-vip> <node2-vip>
```

### 4. Azure AppGW - Configure Listener & Routing (10 min)

```bash
# Backend settings (900 s idle timeout for long-lived database connections)
az network application-gateway settings create \
  --gateway-name <appgw-name> \
  --resource-group <rg-name> \
  --name oracle_1521 \
  --port 1521 \
  --protocol Tcp \
  --timeout 900

# TCP listener
az network application-gateway listener create \
  --gateway-name <appgw-name> \
  --resource-group <rg-name> \
  --name oracle_listener \
  --frontend-port port_1521 \
  --frontend-ip appGwPrivateFrontendIpIPv4

# Routing rule
az network application-gateway routing-rule create \
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
# show-backend-health returns nothing for TCP pools, so test through the gateway
# from a VM that can reach the AppGW private frontend IP. Repeat a few times:
sqlplus <user>/<password>@//<appgw-private-ip>:1521/<service_name> <<< "SELECT instance_name FROM v\$instance;"

# instance_name should alternate between the RAC instances
```

### 6. Confluent Cloud - Configure Egress DNS (5 min)

In Confluent Cloud Console → Environment → Network → DNS:

- **Domain**: the hostname you will use as `connection.host`
- **Example**: `oracle.<your-domain>`
- **Target**: the EAP that routes to the AppGW private frontend IP

**Why**: The connector's hostname must resolve to the AppGW. The name is only a label (it need not match the SCAN or node names); the AppGW forwards to the VIPs.

**If Oracle uses TLS (TCPS):** the name is no longer arbitrary. The connector checks the certificate it is shown against `connection.host`, so the name must be in the certificate's SAN/CN, or hostname validation must be disabled on the connector (less secure). If the AppGW terminates TLS, its certificate must cover the name. See [APPGW-SETUP.md](./APPGW-SETUP.md) step 3.3.

### 7. Deploy JDBC Source Connector (5 min)

Create `oracle-connector.json`:

```json
{
  "name": "oracle-rac-jdbc-source",
  "connector.class": "OracleDatabaseSource",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "<your-api-key>",
  "kafka.api.secret": "<your-api-secret>",
  "tasks.max": "1",
  "connection.host": "oracle.<your-domain>",
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
| "Got minus one from a read call" | Connection redirected or closed before the handshake | `connection.host` must resolve to the AppGW (not a SCAN IP), pool must hold VIPs, listener must be plain TCP |
| "Unknown host specified" | No egress DNS entry for `connection.host` | Add an entry for that hostname in Confluent Cloud, targeting the EAP |
| TLS error: "certificate does not match" / `No subject alternative names matching` | Oracle (or AppGW) certificate doesn't cover the egress DNS name | Use a name that is in the certificate, reissue the certificate, or disable hostname validation (less secure) |
| ORA-12514 on some connections | Service not registered on every pooled node | Register the service on all nodes, or pool only nodes that carry it |
| Backend "Unhealthy" | Firewall/routing issue | Check firewall allows TCP 1521 from AppGW subnet |
| Connector RUNNING but no data | Column mapping wrong | Verify incrementing/timestamp columns exist and have correct format |

---

## Key Points

✅ **AppGW backend = node VIPs** - not the SCAN addresses, not the physical IPs  
✅ **Egress DNS entry for `connection.host`** - resolves to the EAP in front of the AppGW (with TLS, the name must also match the certificate)  
✅ **SCAN bypassed** - Direct node connections, no TNS redirect  
✅ **Service on every pooled node** - the AppGW cannot detect ORA-12514  
✅ **Leave REMOTE_LISTENER / LOCAL_LISTENER at defaults**  
✅ **Idle timeout 900 s** - long-lived JDBC connections  

---

## Total Setup Time: ~40 minutes

For detailed explanations and advanced configuration, see [APPGW-SETUP.md](./APPGW-SETUP.md)
