# Option 4: EAP → Application Gateway → Private Link (Full Private Networking)

A reusable Confluent Cloud EAP points at an Azure Application Gateway in your VNet. The gateway's backend pool holds the **failover group FQDN**; it resolves through your private DNS to the private endpoint of whichever SQL server is currently primary. No public DNS is involved.

## How it works

```
Connector (connection.host = peter-fog.database.windows.net, port 1433)
  → Confluent egress DNS: peter-fog.database.windows.net → EAP
  → EAP → Application Gateway private frontend (TCP listener)
  → backend pool: peter-fog.database.windows.net
       resolved in your VNet: CNAME chain → privatelink.database.windows.net A record
  → private endpoint of the current primary (West US 2 or East US)
```

At failover Azure updates the CNAME chain; the gateway re-resolves the backend and its health probe moves traffic to the new primary. No manual DNS updates.

## Why choose this option

- Fully private: no public SQL endpoint, no public DNS dependency.
- Matches Azure's recommended design for failover groups with private endpoints; the only Confluent-specific part is EAP → AppGW.
- One EAP and one AppGW can serve many connectors. For more Azure SQL setups, add another listener on a different port.
- Cost: AppGW Standard_v2 is roughly $150-180/month (see [../../COST-ANALYSIS.md](../../COST-ANALYSIS.md)); close to zero incremental if you already run one.

## Prerequisites

- Application Gateway v2 with TCP/TLS proxy support and a **private frontend IP**, in a VNet that can reach both SQL private endpoints (the West US 2 VNet in our test, with a private endpoint for each server).
- Private DNS zone `privatelink.database.windows.net` linked to the AppGW VNet, with A records for both servers' private endpoints. Without this the backend FQDN does not resolve to private IPs.
- One Confluent EAP towards the AppGW, and an egress DNS entry for the failover group FQDN pointing at it.

## Setup

1. Add the route (dry run first):

   ```bash
   ./scripts/setup.sh <appgw-rg> <appgw-name> <fog>.database.windows.net 1433
   ./scripts/setup.sh <appgw-rg> <appgw-name> <fog>.database.windows.net 1433 --apply
   ```

   The script creates a backend pool (the FQDN), frontend port, backend TCP settings (port 1433, 15 min idle timeout), listener and routing rule. It has not yet been run against a live gateway, so read the printed commands before applying.

2. Check backend health:

   ```bash
   az network application-gateway show-backend-health --name <appgw-name> -g <appgw-rg>
   ```

   The backend should be Healthy. The secondary's private endpoint is not the target; the FQDN resolves to the primary.

3. Create the egress DNS entry in Confluent for `<fog>.database.windows.net` → the EAP that targets the AppGW private frontend.

4. Deploy the connector (see [../../connector-config/](../../connector-config/)) with `connection.host=<fog>.database.windows.net`.

5. Fail over and verify per [../../docs/FAILOVER-TESTING.md](../../docs/FAILOVER-TESTING.md).

## Notes

- Tune the idle timeout to be longer than the connector's idle/keepalive interval (see the [IBM MQ pattern](../../../ibm-mq/docs/HEARTBEAT-CONFIG.md) for why).
- Source-IP filtering on this path is done with an NSG on the AppGW subnet. Traffic arriving via Private Link is source-NATed, so allow the Private Link IP configuration subnet, not Confluent's IPs.
- A custom TCP health probe can be defined in Terraform (`probe` block, see [../../../oracle-rac/egress-access-points/appgw-scan/appgw.tf](../../../oracle-rac/egress-access-points/appgw-scan/appgw.tf) for the syntax). Probe interval and threshold set how quickly a failover is picked up.
- Test results: failover and failback were validated end to end (records written to the primary in both regions, connector stayed RUNNING).
