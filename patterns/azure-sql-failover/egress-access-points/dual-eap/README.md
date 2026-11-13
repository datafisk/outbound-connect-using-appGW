# Option 3: Dual Egress Access Points (Private Networking with Public DNS)

One Confluent Cloud EAP per region, each connected to that region's Azure SQL server. The connector uses the failover group FQDN; public DNS resolves it to the current primary's regional name, and Confluent egress DNS maps that regional name to the matching EAP.

## How it works

```
connection.host = my-fog.database.windows.net
  │  no egress DNS entry for this name
  ▼
public DNS: my-fog.database.windows.net → CNAME → sql-primary-westus2.database.windows.net   (current primary)
  ▼
Confluent egress DNS: sql-primary-westus2.database.windows.net → EAP (West US 2) → SQL private endpoint
                      sql-secondary-eastus.database.windows.net  → EAP (East US)  → SQL private endpoint
```

After a failover Azure repoints the CNAME at `sql-secondary-eastus…`, and the next connection lands on the East US EAP. No manual changes.

**The one rule:** do **not** create an egress DNS entry for the failover group FQDN. If you do, Confluent resolves it locally to a single EAP and never follows the public CNAME.

## Trade-offs

- No Application Gateway, no extra Azure compute.
- Doubles the EAP footprint against cluster quotas.
- Depends on public DNS for the failover group FQDN (some customers object).
- Validated with the SQL Server sink connector; confirm before relying on it for other connector types.

## Setup

Prerequisites: SQL servers and failover group deployed (see [../../terraform/](../../terraform/)), SQL private endpoints in place, and `az` / `confluent` logged in.

1. Run the preflight check. It verifies the private endpoints, prints the values you need for Confluent, and checks that public DNS returns the CNAME chain:

   ```bash
   ./scripts/setup.sh <resource-group> <fog-name> <server-1> <server-2>
   # e.g. ./scripts/setup.sh my-resource-group my-fog sql-primary-westus2 sql-secondary-eastus
   ```

2. In Confluent Cloud, create one egress access point per region, each targeting the SQL server's Azure resource (the server resource ID printed by the script, subresource `sqlServer`). Field names differ between console and CLI versions, so check the current Confluent egress private link docs. Wait until both show as ready.

3. Add egress DNS entries for the **regional** names only:
   - `<server-1>.database.windows.net` → EAP for region 1
   - `<server-2>.database.windows.net` → EAP for region 2
   - Nothing for `<fog>.database.windows.net`.

4. Deploy the connector with `connection.host=<fog>.database.windows.net` (see [../../connector-config/](../../connector-config/)).

5. Test failover per [../../docs/FAILOVER-TESTING.md](../../docs/FAILOVER-TESTING.md).

## Troubleshooting

- **Connector FAILED, "Could not connect":** check both EAPs are ready, both regional DNS entries exist, and there is no entry for the failover group FQDN. With public access disabled on the SQL servers, a missing regional entry means no path at all.
- **Connector stuck on the old region after failover:** check for a stray egress DNS entry on the failover group FQDN.
- **Confirm the private path:** the SQL `sys.dm_exec_connections` `client_net_address` for the connector login should not be a public IP.
