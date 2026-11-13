# Oracle RAC: Oracle CDC Source Connector (LogMiner)

Fully managed **Oracle CDC Source** connector (`OracleCdcSource`, reads the redo log through Oracle LogMiner) against a 2-node Oracle RAC through an Egress Access Point and an Azure Application Gateway (TCP listener, pool = node VIPs).

> This folder covers the **LogMiner-based** connector only. Shared infrastructure is in [../oracle-rac](../oracle-rac/README.md). The XStream connector is in [../oracle-rac-xstream](../oracle-rac-xstream/README.md).

## TL;DR

- Works end to end; both RAC redo threads are captured. Median latency was about 9 s.
- **Every failure that was tested recovered without manual action**, and no rows were lost or duplicated: graceful stop and hard reset of either node, and a total outage of both nodes (automatic recovery about 12 minutes after the database returned).
- A 20,000-row burst at about 99 rows/s was delivered with the last row 11 s behind the last insert. Higher rates were not tested.
- A service on one node only did not break it (slower reconnects). Still register the service on every pooled node.
- The status field is unreliable during outages: it can read RUNNING while the database is down and FAILED while the connector is reconnecting. Alert on lag.
- `oracle.fan.events.enable` has no use through the gateway (ONS port 6200 is not forwarded); leave it off.

## Contents

| Path | Purpose |
|------|---------|
| [docs/LOGMINER-SETUP.md](./docs/LOGMINER-SETUP.md) | User and grants, supplemental logging, gateway and connector setup |
| [docs/HA-TESTING-LOGMINER.md](./docs/HA-TESTING-LOGMINER.md) | Results of the failure, load and configuration tests, comparison with XStream |
| [connector-config/oracle-logminer.json.template](./connector-config/oracle-logminer.json.template) | Connector configuration with placeholders |

## Related

- [Shared RAC, gateway and egress setup](../oracle-rac/docs/APPGW-SETUP.md)
- [Confluent Cloud Oracle CDC Source documentation](https://docs.confluent.io/cloud/current/connectors/cc-oracle-cdc-source/cc-oracle-cdc-source.html)
