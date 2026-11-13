# Oracle Database (JDBC) Source Setup on Oracle RAC

> **Scope: the fully managed Oracle Database Source connector (`OracleDatabaseSource`), which polls tables with SQL.** It is not log-based CDC: it cannot see deletes or intermediate updates. For CDC use the [XStream](../../oracle-rac-xstream/docs/XSTREAM-SETUP.md) or [LogMiner](../../oracle-rac-logminer/docs/LOGMINER-SETUP.md) connector. Network path (Egress Access Point, Application Gateway, node VIP pool): [APPGW-SETUP.md](../../oracle-rac/docs/APPGW-SETUP.md).

Validated on a 2-node Oracle 19c RAC (OCI DB System) with a CDB and a PDB. Results: [HA-TESTING-JDBC.md](./HA-TESTING-JDBC.md). Confluent documents Oracle 11.2.0.4 and later for this connector.

## What it can and cannot capture

| Captured | Not captured |
|----------|--------------|
| New rows (incrementing mode) | Deletes |
| New and changed rows when a non-nullable timestamp column is also used (timestamp+incrementing) | Intermediate states between two polls |
| | Rows inserted with an ID lower than the highest ID already read (incrementing mode) |

Latency is bounded by `poll.interval.ms` (5 s in the tests).

## How it connects

```
Confluent connector
  -> Egress Access Point -> egress DNS name -> AppGW private frontend :1521
  -> AppGW TCP pool = node VIPs
  -> node listener -> PDB service (registered on EVERY instance)
```

Use a pool of the **node VIPs**, not the SCAN VIP, and a service that exists on every pooled node. Unlike the CDC connectors this one connects to the **PDB** service.

## 1. Database user

A local user in the PDB with `SELECT` on the tables to read. No LogMiner or XStream privileges are needed.

```sql
ALTER SESSION SET CONTAINER = <PDB_NAME>;
CREATE USER <JDBC_USER> IDENTIFIED BY "<PASSWORD>" DEFAULT TABLESPACE USERS QUOTA UNLIMITED ON USERS;
GRANT CREATE SESSION TO <JDBC_USER>;
GRANT SELECT ON <SCHEMA>.<TABLE> TO <JDBC_USER>;
```

Check it through a **node VIP** (not the gateway):

```sql
-- sqlplus <JDBC_USER>@//<node-vip>:1521/<pdb_service>
SELECT COUNT(*) FROM <schema>.<table>;
```

## 2. Database service

Use the PDB service that exists on all instances (the PDB's default service does). A service registered on one instance only fails the connector's configuration validation (see [HA-TESTING-JDBC.md](./HA-TESTING-JDBC.md#6-a-service-on-only-one-instance-fails-validation-jb7)).

## 3. Application Gateway

Backend pool = the node VIPs, TCP listener on 1521, TCP backend setting with idle timeout 900 s. See [../../oracle-rac-xstream/docs/XSTREAM-SETUP.md](../../oracle-rac-xstream/docs/XSTREAM-SETUP.md#4-application-gateway) for notes on probes, `routing-rule` commands and keeping the OCI prefix unique on the hub gateway. The same egress DNS record works for all three connectors.

## 4. Connector configuration

CLI create (`confluent connect cluster create --config-file <file>`), template in [../connector-config/oracle-jdbc.json.template](../connector-config/oracle-jdbc.json.template):

```json
{
  "connector.class": "OracleDatabaseSource",
  "name": "OracleJdbcSourceConnector_RAC",
  "kafka.auth.mode": "SERVICE_ACCOUNT",
  "kafka.service.account.id": "<sa-xxxxxx>",
  "connection.host": "<egress DNS name that resolves to the AppGW frontend>",
  "connection.port": "1521",
  "connection.user": "<JDBC_USER>",
  "connection.password": "<PASSWORD>",
  "db.connection.type": "SERVICE_NAME",
  "db.name": "<PDB service name registered on all instances>",
  "db.timezone": "UTC",
  "ssl.mode": "disabled",
  "table.types": "TABLE",
  "query": "SELECT CAST(ORDER_ID AS NUMBER(18,0)) AS ORDER_ID, CUSTOMER_ID, ORDER_DATE, STATUS, ORDER_TOTAL FROM ORDERMGMT.ORDERS",
  "mode": "incrementing",
  "incrementing.column.name": "ORDER_ID",
  "poll.interval.ms": "5000",
  "batch.max.rows": "1000",
  "topic.prefix": "JDBC.ORDERS",
  "output.data.format": "JSON_SR",
  "tasks.max": "1"
}
```

### Settings that cost time in the tests

| Symptom | Cause and fix |
|---------|---------------|
| `Value "service_name" is not a valid "Database name type"` | `db.connection.type` takes `SERVICE_NAME` (upper case) or `SID`. |
| `Incrementing column: [ORDER_ID] does not exist in table` | With `table.include.list` the `incrementing.column.mapping` takes `regex:column` **without brackets**, for example `ORDERMGMT\.ORDERS:ORDER_ID`. Brackets are for `timestamp.columns.mapping` only. A bracketed name is read literally. |
| `Scale of Decimal value for incrementing column must be 0` | An Oracle `NUMBER` without precision is read as a decimal of undefined scale. `numeric.mapping=best_fit` did **not** fix it. Cast the key in a query as shown (`CAST(... AS NUMBER(18,0))`) and set `incrementing.column.name`. With `query`, do not set `table.include.list`; the topic name is `topic.prefix` itself. |
| `A timestamp column must not be nullable` (documentation) | Timestamp modes need a non-nullable timestamp column. Without one, use `incrementing` mode with an ID that increases in commit order. |
| Rows never arrive although the connector is RUNNING | In `incrementing` mode only IDs above the highest one already read are delivered. Check `SELECT MAX(<id>)` against the IDs of the missing rows. |
| `Unable to validate configuration ... errorCode: 12514` | The validation connection reached a node that does not have the service. Register the service on every pooled node. |
| `Updated connector` but nothing changes | The CLI reports success when the request is accepted. Validation runs afterwards; if it fails the connector keeps its previous settings. Read `trace` in `confluent connect cluster describe <id> -o json` and verify the task's service in `gv$session`. |

Starting point of a new connector: in `incrementing` mode the connector reads the whole table first (35,490 rows in the tests, all delivered). `timestamp.initial=-1` (start from now) applies to the timestamp modes only.

## 5. Verify end to end

```sql
-- in the PDB, as the schema owner
INSERT INTO <schema>.<table> ... ;   -- use an ID higher than every existing ID
COMMIT;
```

The row appears on the topic within about two poll intervals (5 s median in testing). Database-side check:

```sql
SELECT inst_id, service_name, logon_time FROM gv$session WHERE username = '<JDBC_USER>';
```

## 6. Operating notes

- Alert on lag, not only on the status: the status can read RUNNING while the database is down and FAILED while the connector is already reconnecting.
- After a total outage expect about 11 minutes before the connector resumes by itself, then a backlog of delayed rows.
- IDs must increase in commit order. Several writers inserting concurrently can lose rows in incrementing mode.
- Confluent's connector documentation: [Oracle Database Source (JDBC) Connector for Confluent Cloud](https://docs.confluent.io/cloud/current/connectors/cc-oracle-db-source.html).
