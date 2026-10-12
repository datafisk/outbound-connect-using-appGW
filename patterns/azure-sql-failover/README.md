# Azure SQL Failover Pattern

## TL;DR

Azure SQL failover groups rely on CNAME DNS updates, but Confluent Cloud private DNS is A-record only. The failover group FQDN therefore has to be resolved against public DNS, which some customers won't accept. Four approaches work, and all of them give automatic failover with a single connector pointed at the failover group FQDN:

1. **Unrestricted public access**: public SQL endpoints, no firewall whitelisting, Service Endpoints carry the traffic.
2. **Restricted public access**: public endpoints with the firewall and "Allow Azure Services" enabled.
3. **Private networking with public DNS**: one EAP per region, regional names in Confluent egress DNS, CNAMEs resolved via public DNS.
4. **Full private networking**: one reusable EAP to an Application Gateway, to Private Link endpoints in both regions (~$150-180/month for AppGW).

Choose based on security requirements and how many SQL setups you need to cover.

## The Challenge

SQL instances in separate regions share a failover group FQDN (`peter-fog.database.windows.net` in our testing). Azure rewrites CNAME records at failover to point at the current primary.

- Confluent Cloud private DNS does not host CNAMEs, so the failover group FQDN must resolve over the Internet.
- Existing guidance doesn't cover this service or private networking setups, so customers try several configurations and most fail.

See [docs/FAILOVER-TESTING.md](./docs/FAILOVER-TESTING.md) for the full option write-up, the configurations that don't work, and test procedures.

## Options at a Glance

| | Option 1 | Option 2 | Option 3 | Option 4 |
|---|---|---|---|---|
| Summary | Public, no firewall IPs | Public + firewall | Dual EAP, public DNS | EAP → AppGW → PEs |
| SQL public endpoint | Yes | Yes | No | No |
| Private path | No | No | Yes | Yes |
| Public DNS dependency | Yes | Yes | Yes | No |
| EAPs | 0 | 0 | 2 | 1 (reusable) |
| Extra cost | none | none | 2nd EAP, 2 PEs | AppGW ~$150-180/mo |
| Failover | Automatic | Automatic | Automatic | Automatic |

Key caveats:
- **Option 1** relies on SQL authentication alone.
- **Option 2** needs "Allow Azure Services and Resources to access this server", which some customers reject as too broad. Static egress IPs only work cross region (same-region Azure NAT hides the source IP). Confluent does not expose connector VNet/subnet names, so cross-tenant VNet whitelisting isn't an option.
- **Option 3** doubles the EAP footprint against cluster quotas. The failover group FQDN must **not** have an egress DNS entry.
- **Option 4** scales best when several Azure SQL setups share the AppGW (cycle listener ports). EAP and AppGW can be reused by other connectors.

## Setup

- Options 1 and 2: no EAP needed. Open the SQL servers' public access as described in [docs/FAILOVER-TESTING.md](./docs/FAILOVER-TESTING.md), then deploy the connector.
- Option 3: [egress-access-points/dual-eap/](./egress-access-points/dual-eap/)
- Option 4: [egress-access-points/appgw/](./egress-access-points/appgw/)

Connector config for all options is in [connector-config/](./connector-config/). Set `connection.host` to the failover group FQDN:

```bash
cd connector-config/
./generate-config.sh
confluent connect cluster create --config-file sql-sink.generated.json
```

Note that the sink connector auto-creates a table named after the topic (e.g. `dbo.[test-orders]`).

## Testing Failover

```bash
# Fail over to the other region
az sql failover-group set-primary --name <fog> --resource-group <rg> --server <other-server>

# Connector should stay RUNNING; produce records and check the new primary
confluent connect cluster list
```

Full procedures: [docs/FAILOVER-TESTING.md](./docs/FAILOVER-TESTING.md).

## Components

- Two Azure SQL servers in different regions, in one failover group
- Private endpoints for both servers (Options 3 and 4)
- Confluent Egress Access Point(s) (Options 3 and 4)
- Application Gateway (Option 4)
- Confluent MicrosoftSqlServerSink connector

## Prerequisites

- Confluent Cloud cluster with Egress Access Point support (Options 3 and 4)
- Azure subscription, Azure CLI and Confluent CLI authenticated
- Terraform >= 1.0 (SQL infrastructure example)

## Cost

SQL compute is the same across all options and dominates the bill. The options differ only in connectivity cost. See [COST-ANALYSIS.md](./COST-ANALYSIS.md). Confluent-side EAP charges are not included in those figures; check current Confluent pricing for your cluster type.

## Documentation

- [docs/FAILOVER-TESTING.md](./docs/FAILOVER-TESTING.md): options, non-working configs, test procedures
- [COST-ANALYSIS.md](./COST-ANALYSIS.md): cost breakdown
- [egress-access-points/dual-eap/](./egress-access-points/dual-eap/): Option 3
- [egress-access-points/appgw/](./egress-access-points/appgw/): Option 4

## Related Patterns

- [Oracle RAC](../oracle-rac/): similar HA problem solved with AppGW
- [IBM MQ](../ibm-mq/): AppGW idle-timeout handling
