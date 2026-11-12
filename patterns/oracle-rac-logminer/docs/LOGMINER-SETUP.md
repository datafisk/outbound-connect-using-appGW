# Oracle CDC Source (LogMiner) Setup on Oracle RAC

> **Scope: the fully managed Oracle CDC Source connector (`OracleCdcSource`), which uses Oracle LogMiner.** For the XStream CDC connector see [XSTREAM-SETUP.md](../../oracle-rac-xstream/docs/XSTREAM-SETUP.md). The network path (Egress Access Point, Application Gateway, node VIP pool) is the same for both; see [APPGW-SETUP.md](../../oracle-rac/docs/APPGW-SETUP.md).

Validated on a 2-node Oracle 19c RAC (OCI DB System) with a CDB (`RACDB`) and a PDB (`XSTRPDB`). Results: [HA-TESTING-LOGMINER.md](./HA-TESTING-LOGMINER.md). Confluent supports Oracle 19c and later for this connector.

## How it connects

```
Confluent connector
  -> Egress Access Point -> egress DNS name -> AppGW private frontend :1521
  -> AppGW TCP pool = node VIPs
  -> node listener -> CDB service (registered on EVERY instance)
```

The connector connects to the **CDB** (LogMiner runs in the root container) and reads the PDB's tables by filtering on the PDB name. As with XStream, point the gateway pool at the **node VIPs**, not the SCAN VIP: the SCAN redirect target cannot be resolved by Confluent. Register the service on every instance in the pool.

## 1. Database prerequisites

Run as SYSDBA.

```sql
-- ARCHIVELOG must be on (on RAC, mount the database with srvctl; see Confluent's prerequisites page)
SELECT log_mode FROM v$database;

-- Supplemental logging: the connector defaults to full (oracle.supplemental.log.level=full)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER SESSION SET CONTAINER = <PDB_NAME>;
ALTER TABLE <SCHEMA>.<TABLE> ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;   -- for every captured table
-- Or, for all tables at once, from the root: ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
```

If you already prepared the database for the XStream connector, ARCHIVELOG and table-level supplemental logging are already in place.

## 2. Connector user and role

A **common user** (prefix `C##`) in the root, with a role holding the LogMiner grants. Replace `<PDB_NAME>`, `<SCHEMA>` and the password. Oracle password profiles may require several digits and special characters.

```sql
ALTER SESSION SET CONTAINER = CDB$ROOT;
CREATE ROLE C##CDC_PRIVS CONTAINER=ALL;
CREATE USER C##CDCUSER IDENTIFIED BY "<PASSWORD>" CONTAINER=ALL;
ALTER USER C##CDCUSER QUOTA UNLIMITED ON USERS CONTAINER=ALL;
ALTER USER C##CDCUSER SET CONTAINER_DATA = (CDB$ROOT, <PDB_NAME>) CONTAINER=CURRENT;
GRANT C##CDC_PRIVS TO C##CDCUSER CONTAINER=ALL;

GRANT CONNECT, CREATE SESSION, LOGMINING TO C##CDC_PRIVS CONTAINER=ALL;
GRANT SELECT ON V_$DATABASE            TO C##CDC_PRIVS CONTAINER=ALL;
GRANT SELECT ON V_$INSTANCE            TO C##CDC_PRIVS CONTAINER=ALL;
GRANT SELECT ON V_$THREAD              TO C##CDC_PRIVS CONTAINER=ALL;
GRANT SELECT ON V_$PARAMETER           TO C##CDC_PRIVS CONTAINER=ALL;
GRANT SELECT ON V_$NLS_PARAMETERS      TO C##CDC_PRIVS CONTAINER=ALL;
GRANT SELECT ON V_$TIMEZONE_NAMES      TO C##CDC_PRIVS CONTAINER=ALL;
GRANT SELECT ON V_$LOG                 TO C##CDC_PRIVS CONTAINER=ALL;
GRANT SELECT ON V_$LOGFILE             TO C##CDC_PRIVS CONTAINER=ALL;
GRANT SELECT ON V_$LOGMNR_CONTENTS     TO C##CDC_PRIVS CONTAINER=ALL;
GRANT SELECT ON V_$ARCHIVED_LOG        TO C##CDC_PRIVS CONTAINER=ALL;
GRANT SELECT ON V_$ARCHIVE_DEST_STATUS TO C##CDC_PRIVS CONTAINER=ALL;
GRANT SELECT ON DBA_PDBS               TO C##CDC_PRIVS CONTAINER=ALL;
GRANT SELECT ON CDB_TABLES             TO C##CDC_PRIVS CONTAINER=ALL;
GRANT SELECT ON CDB_TAB_PARTITIONS     TO C##CDC_PRIVS CONTAINER=ALL;
GRANT SELECT ON DBA_SUPPLEMENTAL_LOGGING TO C##CDC_PRIVS CONTAINER=ALL;
GRANT EXECUTE ON SYS.DBMS_LOGMNR       TO C##CDC_PRIVS CONTAINER=ALL;
GRANT EXECUTE ON SYS.DBMS_LOGMNR_D     TO C##CDC_PRIVS CONTAINER=ALL;

ALTER SESSION SET CONTAINER = <PDB_NAME>;
GRANT SELECT ON <SCHEMA>.<TABLE> TO C##CDC_PRIVS;      -- every captured table
GRANT FLASHBACK ON <SCHEMA>.<TABLE> TO C##CDC_PRIVS;   -- only needed for the initial snapshot (start.from=snapshot)
```

The Confluent page lists two `V_$ARCHIVE_DEST_STATUS` grants without the `C##` prefix in its multitenant examples; use the prefixed role as above.

Check the grants by logging in as the connector user through a **node VIP** (not the gateway) and reading the views:

```sql
-- sqlplus C##CDCUSER@//<node-vip>:1521/<cdb_service>
SELECT COUNT(*) FROM v$thread;          -- expect the number of RAC instances (2)
SELECT COUNT(*) FROM v$archived_log;
SELECT COUNT(*) FROM v$logmnr_contents WHERE 1=0;
```

Confluent also provides `check_prerequisites.sql` and `oracle-readiness.sql` (see its Oracle prerequisites page). They were not run in these tests.

## 3. Database service

Use a service that exists on **all** instances. The default CDB service (`<db_unique_name>.<db_domain>`) does. A service on one instance only still worked in testing but made the connector's reconnects slower (see [HA-TESTING-LOGMINER.md](./HA-TESTING-LOGMINER.md#6-a-service-on-only-one-instance-does-not-break-this-connector-lm7)), so avoid it.

## 4. Application Gateway

Backend pool = the node VIPs, TCP listener on 1521, TCP backend setting with idle timeout 900 s. See [XSTREAM-SETUP.md](../../oracle-rac-xstream/docs/XSTREAM-SETUP.md#4-application-gateway) for notes on probes, `routing-rule` commands and keeping the OCI prefix unique on the hub gateway. The same egress DNS record works for both connectors.

## 5. Kafka and Schema Registry

- A service account with permission to create topics and read/write them. In testing the connector created the table topics itself (`LM.<SCHEMA>.<TABLE>`).
- Schema Registry must be enabled for AVRO, JSON_SR and PROTOBUF formats.
- Use a topic template that cannot collide with another connector on the same database. This guide uses `LM.${schemaName}.${tableName}`.

## 6. Connector configuration

CLI create (`confluent connect cluster create --config-file <file>`):

```json
{
  "connector.class": "OracleCdcSource",
  "name": "OracleCdcSourceConnector_LM",
  "kafka.auth.mode": "SERVICE_ACCOUNT",
  "kafka.service.account.id": "<sa-xxxxxx>",
  "oracle.server": "<egress DNS name that resolves to the AppGW frontend>",
  "oracle.port": "1521",
  "oracle.sid": "<CDB name, for example RACDB>",
  "oracle.service.name": "<CDB service registered on all instances>",
  "oracle.pdb.name": "<PDB_NAME>",
  "oracle.username": "C##CDCUSER",
  "oracle.password": "<PASSWORD>",
  "table.inclusion.regex": "<PDB_NAME>[.]<SCHEMA>[.](TABLE1|TABLE2)",
  "table.topic.name.template": "LM.${schemaName}.${tableName}",
  "start.from": "current",
  "oracle.fan.events.enable": "false",
  "output.data.key.format": "JSON_SR",
  "output.data.value.format": "JSON_SR",
  "tasks.max": "1"
}
```

Notes:
- `table.inclusion.regex` is matched case-sensitively against `<PDB>.<SCHEMA>.<TABLE>` in upper case for a PDB.
- `start.from=current` skips the initial snapshot. The default is `snapshot`, which needs the FLASHBACK grants.
- `oracle.fan.events.enable` should stay `false`: FAN uses the ONS port (6200 here), which the gateway does not forward.
- One connector instance reads the tables of one PDB (per Confluent's documentation). Run one connector per PDB.
- Per Confluent's documentation the connector's redo log topic has a single partition and must not be shared between connectors.

## 7. Verify end to end

```sql
-- in the PDB, as the schema owner
INSERT INTO <schema>.<table> ... ;
COMMIT;
```

The row appears on `LM.<SCHEMA>.<TABLE>` about 8 to 10 s later (median in testing). Database-side checks:

```sql
SELECT inst_id, sid, session_id FROM gv$logmnr_session;                         -- the active mining session
SELECT inst_id, COUNT(*) FROM gv$session WHERE username = 'C##CDCUSER' GROUP BY inst_id;
```

## 8. Operating notes

- Alert on end-to-end lag. The status can read RUNNING while the database is unreachable and FAILED while the connector is already reconnecting.
- After a total outage expect about 10 to 12 minutes before the connector resumes by itself, then a backlog of delayed rows.
- If the XStream connector also runs on this database, it competes for the same redo logs; its paused session may stay attached.
- Confluent's supported range, restart and failover statements are in the [connector documentation](https://docs.confluent.io/cloud/current/connectors/cc-oracle-cdc-source/cc-oracle-cdc-source.html).
