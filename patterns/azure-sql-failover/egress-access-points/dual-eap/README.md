# Option 3: Dual Egress Access Points (Private Networking with Public DNS)

One Confluent Cloud EAP per region, each connected to that region's Azure SQL server. The connector uses the failover group FQDN; public DNS resolves it to the current primary's regional name, and Confluent egress DNS maps that regional name to the matching EAP.

## How it works

```
connection.host = peter-fog.database.windows.net
  │  no egress DNS entry for this name
  ▼
public DNS: peter-fog.database.windows.net → CNAME → pg-uswest2.database.windows.net   (current primary)
  ▼
Confluent egress DNS: pg-uswest2.database.windows.net → EAP (West US 2) → SQL private endpoint
                      pg-useast.database.windows.net  → EAP (East US)  → SQL private endpoint
```

After a failover Azure repoints the CNAME at `pg-useast…`, and the next connection lands on the East US EAP. No manual changes.

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
   # e.g. ./scripts/setup.sh petergustafss-test peter-fog pg-uswest2 pg-useast
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

## Cost

Azure side: roughly $7.30/month per private endpoint plus $0.01/GB processed. Confluent-side EAP charges depend on your cluster type and are not included here; check current Confluent pricing. See [../../COST-ANALYSIS.md](../../COST-ANALYSIS.md).
