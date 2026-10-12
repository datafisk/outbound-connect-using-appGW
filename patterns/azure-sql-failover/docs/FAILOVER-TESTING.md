# Azure SQL Failover Testing Guide

Options, trade-offs and test procedures for connecting Confluent Cloud connectors to Azure SQL Server failover groups.

## Table of Contents

- [Design & Challenge](#design--challenge)
- [Working Options](#working-options)
- [Why Other Configurations Fail](#why-other-configurations-fail)
- [Testing Procedures](#testing-procedures)
- [Test Results Summary](#test-results-summary)
- [Key Limitations Summary](#key-limitations-summary)

---

## Design & Challenge

SQL instances deployed in separate regions (useast & uswest2 in our testing) are mapped into the same failover group with a shared FQDN (`peter-fog`). Azure updates that FQDN with CNAME records at failover, pointing at whichever regional server is primary. Cross-region connectivity is implied: either the databases have public endpoints, or private endpoints that are reachable cross region.

This is a problem for Confluent Cloud connectors because:

1. **Confluent Cloud private DNS is A-record only.** It does not host CNAMEs, so the shared failover group FQDN must resolve via the Internet (public DNS). Some customers object to this and want a fully private solution.
2. **Our docs don't give accurate guidance** for this service, in particular for private networking setups.
3. The result is customers trying various options and configurations with a **high failure rate**.

---

## Working Options

For all options, a **single connector** is configured with the failover group FQDN as destination host.

### Option 1: Unrestricted Public IP Access

Azure SQL servers on public endpoints, **no** firewall IP whitelisting.

- Azure SQL AuthN/AuthZ is the sole security control.
- Traffic uses the Confluent Cloud Service Endpoints, routing straight from the connector VNet into the SQL service.
- Public DNS chases the CNAMEs; no manual DNS updates at failover.

### Option 2: Restricted Public IP Access

Azure SQL servers on public endpoints **with** service firewall IP whitelisting.

- Firewall enabled with "Allow Azure Services and Resources to access this server" checked, so connector traffic is allowed through automatically.
- Some customers won't accept "Allow Azure Services…" because of its blanket nature.
- Clusters that support Static Egress IPs can only use them cross region (Azure same-region NAT hides the source IPs).
- Confluent does not expose connector VNet/subnet names for cross-tenant VNet whitelisting. That only works within the same region and would be a bad idea for multi-tenant Connect anyway.

### Option 3: Private Networking with Public DNS

Dual Confluent Cloud EAPs, one direct to each Azure SQL environment, with CNAME resolution from public DNS to Confluent Cloud private DNS.

- No Application Gateway.
- The failover group FQDN is resolved against public DNS; the CNAME chain is followed until it reaches a regional name that matches a Confluent egress DNS entry, which routes to the right EAP.
- No manual DNS updates at failover.
- Some customers may have concerns about relying on public DNS.
- Cheaper than AppGW, but doubles the EAP footprint against cluster quotas.

Setup: [../egress-access-points/dual-eap/](../egress-access-points/dual-eap/)

### Option 4: Full Private Networking, High Scalability

A reusable Confluent Cloud EAP to an Application Gateway, to customer-hosted Private Link endpoints for the SQL servers in both regions.

- Aligns with the recommended Azure design for failover groups with private endpoints; the Confluent-specific part is only EAP → AppGW.
- Single endpoint for the SQL connector (`peter-fog.database.windows.net`).
- AppGW routes to the correct primary based on DNS-driven health probes and chases the Azure-managed CNAME chains.
- No manual DNS updates at failover.
- Slightly higher cost, but scales well when several Azure SQL setups are in scope (listener ports can be cycled on the same AppGW).
- The EAP and AppGW can be reused by other services and connectors.

Setup: [../egress-access-points/appgw/](../egress-access-points/appgw/)

### Comparison

| | Option 1 | Option 2 | Option 3 | Option 4 |
|---|---|---|---|---|
| SQL public endpoint | Yes | Yes | No (PE only) | No (PE only) |
| Private path to SQL | No (backbone via Service Endpoints) | No | Yes | Yes |
| Depends on public DNS | Yes | Yes | Yes | No (resolved inside your VNet) |
| EAPs needed | 0 | 0 | 2 | 1 (reusable) |
| Extra Azure component | – | – | – | Application Gateway |
| Automatic failover | Yes | Yes | Yes | Yes |

---

## Why Other Configurations Fail

These are the configurations customers commonly try first. They do not give automatic failover with private connectivity.

### Single EAP with the failover group FQDN as an egress DNS entry

- Egress DNS entry `peter-fog.database.windows.net` → EAP in one region.
- At failover the entry still points at the old region; it must be updated manually, and the connector is down until it is.
- The single EAP is a single point of failure for the connector.
- You cannot add a second EAP under the same DNS name to cover the other region.

### Two EAPs, but the failover group FQDN also in egress DNS

- If an egress DNS entry exists for the failover group FQDN, Confluent resolves it there and never follows the public CNAME chain, so you are back to the single-target problem above. Option 3 only works when the **failover group FQDN has no egress DNS entry** and only the regional FQDNs do.
- Using the regional FQDNs directly (one connector per region, start/stop depending on primary) works but needs manual orchestration, and the inactive connector sits in FAILED.

### Service Endpoints with cross-tenant VNet whitelisting

- VNet rules are not officially supported cross tenant, and Confluent does not expose connector subnet names.
- Whitelisting a subnet on a multi-tenant (ESKU) cluster would expose the service to other customers.
- Confluent does not expose stable connector IP ranges via API for public IP whitelisting on private clusters; ranges must be discovered and maintained by hand and may change.
- With "Deny public network access" = Yes, Service Endpoint traffic is blocked as well.

---

## Testing Procedures

### Initial Setup Verification

1. **Verify Failover Group Status:**

```bash
az sql failover-group show \
  --name peter-fog \
  --resource-group petergustafss-test \
  --server pg-uswest2 \
  --query '{primary:replicationRole,secondary:partnerServers[0].replicationRole}'
```

2. **Verify Private Endpoints:**

```bash
# Check West US 2 Private Endpoint
az network private-endpoint show \
  --name pg-uswest2-pe \
  --resource-group petergustafss-test \
  --query 'privateLinkServiceConnections[0].privateLinkServiceConnectionState.status'

# Check East US Private Endpoint
az network private-endpoint show \
  --name pg-useast-pe \
  --resource-group petergustafss-test \
  --query 'privateLinkServiceConnections[0].privateLinkServiceConnectionState.status'
```

3. **Verify Connector Status:**

```bash
confluent connect cluster list \
  --environment t36181 \
  --cluster lkc-mqj017 | grep "fog-failvoer-test"
```

### Test 1: Data Flow to Primary Region

**Objective:** Verify data flows to current primary SQL server

**Steps:**

1. Check current primary:
```bash
az sql failover-group show \
  --name peter-fog \
  --resource-group petergustafss-test \
  --server pg-uswest2 \
  --query '{primary:partnerServers[0].replicationRole}'
```

2. Produce test messages to Kafka topic:
```bash
# Produce 3 test messages via Confluent Cloud console
# or use confluent kafka topic produce command
```

3. Verify messages written to primary SQL server:
```sql
-- Connect to current primary
SELECT COUNT(*) FROM [dbo].[test-orders];

-- View latest records
SELECT TOP 5 * FROM [dbo].[test-orders] ORDER BY order_id DESC;
```

4. Verify connector status:
```bash
confluent connect cluster describe lcc-nv5y8ok \
  --environment t36181 \
  --cluster lkc-mqj017
```

**Expected Results:**
- ✅ Connector status: RUNNING
- ✅ Messages appear in primary SQL database
- ✅ No errors in connector logs

### Test 2: Failover to Secondary Region

**Objective:** Verify automatic failover with zero connector downtime

**Steps:**

1. Record current state:
```bash
# Current primary
CURRENT_PRIMARY=$(az sql failover-group show \
  --name peter-fog \
  --resource-group petergustafss-test \
  --server pg-uswest2 \
  --query 'replicationRole' -o tsv)

echo "Current primary: $CURRENT_PRIMARY"

# Record count before failover
# Connect to database and run:
SELECT COUNT(*) as count_before_failover FROM [dbo].[test-orders];
```

2. Trigger failover:
```bash
# If current primary is West US 2, failover to East US
az sql failover-group set-primary \
  --name peter-fog \
  --resource-group petergustafss-test \
  --server pg-useast

# Wait 30-60 seconds for failover to complete
sleep 60
```

3. Verify new primary:
```bash
az sql failover-group show \
  --name peter-fog \
  --resource-group petergustafss-test \
  --server pg-uswest2 \
  --query '{primary:partnerServers[0].replicationRole,replicationState:replicationState}'
```

4. **CRITICAL**: Check connector status during/after failover:
```bash
confluent connect cluster describe lcc-nv5y8ok \
  --environment t36181 \
  --cluster lkc-mqj017 | grep Status
```

5. Produce new test messages (3-5 messages):
```bash
# Produce messages via Confluent Cloud console
```

6. Verify messages written to NEW primary:
```sql
-- Connect to new primary (East US if failover from West)
SELECT COUNT(*) as count_after_failover FROM [dbo].[test-orders];

-- View latest records (should show new messages)
SELECT TOP 5 * FROM [dbo].[test-orders] ORDER BY order_id DESC;
```

7. Verify replication to secondary:
```sql
-- Connect to secondary (West US if failover to East)
SELECT COUNT(*) FROM [dbo].[test-orders];
-- Should match primary after replication catches up
```

**Expected Results:**
- ✅ Failover completes in 30-60 seconds
- ✅ Connector status: RUNNING (never goes to FAILED)
- ✅ New messages written to new primary
- ✅ Data replicated to new secondary
- ✅ Zero connector downtime
- ✅ Zero manual intervention required

### Test 3: Failback to Original Region

**Objective:** Verify bidirectional failover works

**Steps:**

1. Trigger failback:
```bash
# Failback to original primary (West US 2)
az sql failover-group set-primary \
  --name peter-fog \
  --resource-group petergustafss-test \
  --server pg-uswest2

sleep 60
```

2. Verify connector remained healthy:
```bash
confluent connect cluster describe lcc-nv5y8ok \
  --environment t36181 \
  --cluster lkc-mqj017
```

3. Produce test messages and verify they appear in West US 2

**Expected Results:**
- ✅ Connector stays RUNNING through failback
- ✅ Messages flow to West US 2 (original primary)
- ✅ No errors or downtime

### Test 4: Connection Validation

**Objective:** Verify traffic is using Private Link, not public endpoints

**Method 1: Check Active Connections in SQL Server**

```sql
-- Run on primary SQL server
SELECT 
    session_id,
    login_name,
    client_net_address,
    client_tcp_port,
    connect_time,
    last_read,
    last_write
FROM sys.dm_exec_connections
WHERE login_name = 'confluent'
ORDER BY connect_time DESC;
```

**Expected Results:**
- `client_net_address` should be **172.200.12.x** (Private Endpoint IP)
- If showing public IP, traffic is NOT using Private Link

**Method 2: Disable Public Access**

```bash
# Disable public network access on both servers
az sql server update \
  --name pg-uswest2 \
  --resource-group petergustafss-test \
  --set publicNetworkAccess=Disabled

az sql server update \
  --name pg-useast \
  --resource-group petergustafss-test \
  --set publicNetworkAccess=Disabled
```

**Expected Results:**
- ✅ Connector continues to work (proves it's using Private Link)
- If connector fails, it was relying on public endpoint

---

## Test Results Summary

Tested with failover group `peter-fog` (`pg-uswest2` West US 2, `pg-useast` East US), connector `lcc-nv5y8ok` (MicrosoftSqlServerSink, topic `test-orders`, AVRO, auto-create).

| Option | Result |
|--------|--------|
| 3: Dual EAP, regional egress DNS entries only | Worked: connector follows the failover group via public CNAME resolution. Validated by the user (and observed by accident while an EAP-per-region setup was left in place during other tests). |
| 4: EAP → AppGW → PEs | Worked: records written to the primary in both regions across failover and failback, connector stayed RUNNING. After the tests the SQL servers were opened to public access to verify rows from outside. |
| Single EAP + failover FQDN egress entry | Failed at failover (manual DNS update needed). |
| No egress DNS entries, public access blocked | Connector FAILED, as expected. |

Note: the connector auto-creates a table named after the topic (`dbo.[test-orders]`), not the pre-created `SalesOrders` table. Check that table when verifying writes.

Not yet re-run cleanly: a controlled Option 1 / Option 2 test and a measured failover timing for Option 3.

---

## Key Limitations Summary

### Confluent Cloud

1. Egress DNS is A-record only and does not chase CNAMEs.
2. Two EAPs cannot share the same DNS name, so one name cannot transparently cover both regions.
3. Connector VNet/subnet names and egress IP ranges are not exposed via API, which rules out stable VNet/IP whitelisting.

### Azure

4. VNet rules do not work cross tenant; only IP-based filtering is available.
5. Private Link endpoints are resource-specific; there is no private endpoint for the failover group itself.

### Resolution behaviour (Option 3)

6. Option 3 relies on the connector's resolution path falling back to public DNS for the failover group FQDN and then matching the resulting regional name against egress DNS. It has been validated with the SQL Server connector; confirm it before relying on it for other connector types.

---

## Troubleshooting

### Connector Shows "Could not connect to database"

**Cause:** No route to SQL server

**Check:**
1. Verify EAP DNS entries exist in Confluent egress
2. Verify Private Endpoints are connected (status: Approved)
3. Verify SQL server public access settings match connectivity approach

### Connector Fails After Failover

**Cause:** Using single EAP or incorrect DNS configuration

**Solution:** Use Option 3 (regional egress DNS entries only, none for the failover group FQDN) or Option 4 (AppGW)

### Data Not Appearing in SQL Server

**Cause:** Connector writing to wrong table or wrong database

**Check:**
1. Verify connector's `db.name` configuration
2. Check for auto-created tables matching topic name
3. Verify connector task status (not just connector status)

### Replication Lag Between Regions

**Expected Behavior:** 
- Geo-replication has inherent latency (typically seconds)
- Check `replicationState` in failover group

```bash
az sql failover-group show \
  --name peter-fog \
  --resource-group petergustafss-test \
  --server pg-uswest2 \
  --query replicationState
```

States:
- `SEEDING`: Initial sync in progress
- `CATCH_UP`: Secondary catching up to primary
- `SYNCHRONIZED`: Fully synchronized

---

## Related Documentation

- [../README.md](../README.md) - Pattern overview
- [../COST-ANALYSIS.md](../COST-ANALYSIS.md) - Cost breakdown
- [QUICKSTART.md](./QUICKSTART.md) - Step-by-step deployment guide
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Common issues

---

## References

- [Azure SQL Failover Groups Documentation](https://docs.microsoft.com/azure/sql-database/sql-database-auto-failover-group)
- [Azure Private Link Documentation](https://docs.microsoft.com/azure/private-link/)
- [Confluent Cloud Private Networking](https://docs.confluent.io/cloud/current/networking/private-networking.html)
