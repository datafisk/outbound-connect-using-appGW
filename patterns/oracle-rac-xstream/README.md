# Oracle RAC: XStream CDC Source Connector

Fully managed **Oracle XStream CDC Source** connector reading a 2-node Oracle RAC through an Egress Access Point and an Azure Application Gateway (TCP listener, pool = node VIPs).

> This folder covers the **XStream** connector only. Shared infrastructure (RAC on OCI, Application Gateway, egress) is in [../oracle-rac](../oracle-rac/README.md). The LogMiner-based connector is in [../oracle-rac-logminer](../oracle-rac-logminer/README.md).

## TL;DR

- Works end to end: changes arrive in Kafka about 3 to 5 s after commit; no rows were lost or duplicated in any test.
- **Recovery after some failures is manual.** If the RAC instance hosting the XStream outbound server goes down, `XOUT` is DISABLED and the connector does not recover on its own (observed 12 to 63 minutes). Re-enable `XOUT`, then pause and resume the connector.
- The connector status can read RUNNING while nothing flows. Monitor `dba_xstream_outbound.status` and lag.
- A database service that exists on only one RAC node breaks the connector when the gateway pool holds both VIPs (`ORA-12514`). For RAC One Node use a pool with the active node's VIP only.
- Per Confluent's documentation no additional Oracle license is needed for the Confluent connector.

## Contents

| Path | Purpose |
|------|---------|
| [docs/XSTREAM-SETUP.md](./docs/XSTREAM-SETUP.md) | Database, outbound server, gateway and connector setup, including the RAC walk-through |
| [docs/HA-TESTING-XSTREAM.md](./docs/HA-TESTING-XSTREAM.md) | Node stop, hard reset, both-nodes and single-instance results, recovery runbook, limits |
| [connector-config/oracle-xstream.json.template](./connector-config/oracle-xstream.json.template) | Connector configuration with placeholders |

## Related

- [Shared RAC, gateway and egress setup](../oracle-rac/docs/APPGW-SETUP.md)
- [Troubleshooting](../oracle-rac/docs/TROUBLESHOOTING.md)
- [Confluent Cloud XStream connector documentation](https://docs.confluent.io/cloud/current/connectors/cc-oracle-xstream-cdc-source/cc-oracle-xstream-cdc-source-features.html)
