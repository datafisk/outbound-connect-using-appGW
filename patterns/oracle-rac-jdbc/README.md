# Oracle RAC: Oracle Database (JDBC) Source Connector

Fully managed **Oracle Database (JDBC) Source** connector reading a 2-node Oracle RAC through an Egress Access Point and an Azure Application Gateway (TCP listener, pool = node VIPs).

> This folder covers the **JDBC polling** connector only. It is not log-based CDC. Shared infrastructure is in [../oracle-rac](../oracle-rac/README.md). CDC connectors: [XStream](../oracle-rac-xstream/README.md) and [LogMiner](../oracle-rac-logminer/README.md).

## TL;DR

- Simplest to set up (a `SELECT`-only user, no redo access) and the lowest latency in the tests (median 5 s, equal to the 5 s poll interval).
- **Least affected by node failures:** graceful stops and hard resets of either node never took it out of RUNNING; a total outage of both nodes recovered by itself about 11 minutes after the database returned. No rows were lost or duplicated in the valid tests.
- A 20,000-row burst at about 99 rows/s was delivered with the last row 2 s behind the last insert.
- **Not CDC:** no deletes, no intermediate updates. In incrementing mode rows with an ID lower than the highest one already read are silently skipped.
- Setup pitfalls: `db.connection.type=SERVICE_NAME`, incrementing mapping without brackets, and an unconstrained Oracle `NUMBER` key must be cast in a query. See [docs/JDBC-SETUP.md](./docs/JDBC-SETUP.md).
- A service on only one RAC node fails config validation (`ORA-12514`); the CLI still prints `Updated connector`, so check the connector `trace`.

## Contents

| Path | Purpose |
|------|---------|
| [docs/JDBC-SETUP.md](./docs/JDBC-SETUP.md) | User, service, gateway and connector setup, with the pitfalls found in testing |
| [docs/HA-TESTING-JDBC.md](./docs/HA-TESTING-JDBC.md) | Node stop, hard reset, both-nodes, load and configuration results, limits |
| [connector-config/oracle-jdbc.json.template](./connector-config/oracle-jdbc.json.template) | Connector configuration with placeholders |

## Related

- [Connector comparison (XStream, LogMiner, JDBC)](../oracle-rac/docs/CONNECTOR-COMPARISON.md)
- [Shared RAC, gateway and egress setup](../oracle-rac/docs/APPGW-SETUP.md)
- [Confluent Cloud Oracle Database Source documentation](https://docs.confluent.io/cloud/current/connectors/cc-oracle-db-source.html)
