# Oracle RAC High Availability Testing: Oracle JDBC Source Connector (JDBC only)

> **Scope: this document covers the fully managed Oracle Database (JDBC) Source connector (`OracleDatabaseSource`), which polls tables with SQL.** It does not apply to the XStream connector ([HA-TESTING-XSTREAM.md](../../oracle-rac-xstream/docs/HA-TESTING-XSTREAM.md)) or the LogMiner-based Oracle CDC Source connector ([HA-TESTING-LOGMINER.md](../../oracle-rac-logminer/docs/HA-TESTING-LOGMINER.md)). Setup: [JDBC-SETUP.md](./JDBC-SETUP.md).

## Summary

The same 2-node Oracle RAC on OCI, Egress Access Point, Application Gateway (TCP listener, pool = both node VIPs) and the same failure scenarios as the XStream and LogMiner tests were used.

**Main result: the JDBC connector was the least affected by node failures.** Graceful stops and hard resets of either node never took it out of RUNNING and it needed no manual action. After a total outage of both nodes it recovered by itself about 11 minutes after the database returned. No row was lost or duplicated in any test that was valid. A database service that exists on only one node fails the connector's configuration validation, as with XStream.

| # | Scenario | Connector status | Recovery | Rows in Kafka |
|---|----------|------------------|----------|---------------|
| JB1 | Baseline, inserts from each node (run one after the other) | RUNNING | n/a | 14/14 from each node, each once |
| JB3 | Graceful stop of racnode1, 3 min | RUNNING throughout | none needed | 751/751, 0 dups, median latency 5 s, max 10 s |
| JB4 | Graceful stop of racnode2 (held the connector's session), 3 min | RUNNING throughout | Session on instance 1 within about 1.5 min | 749/749, 0 dups, max latency 11 s |
| JB6A | Hard reset of racnode1 (session host) | RUNNING throughout | Session on instance 2 about 1 min after the reset | 591/591, 0 dups, largest gap 35 s |
| JB6B | Hard reset of racnode2 (session host) | RUNNING throughout | Session on instance 1 | 591/591, 0 dups, largest gap 50 s |
| JB5 | Both nodes stopped for 3 min, then started | RUNNING for the first about 4.5 min of the outage, FAILED 23:12:37 to 23:28:27, RUNNING 23:28:46 | **Automatic**, about 11 min after both instances were OPEN | 43/43 before; 1350/1350 after, 0 dups, max latency 643 s (backlog) |
| JB2 | Load: 20,000 rows at about 99 rows/s for 203 s | RUNNING | n/a | 20,000/20,000, 0 dups; median latency 5 s, p95 9 s, max 10 s; last row 2 s after the last insert |
| JB7 | Service on one instance only, both VIPs in the pool | Config validation failed 5 of 5 times (`errorCode 12514`) | n/a | **Not tested**, see finding 6 |

## Test environment

| Item | Value |
|------|-------|
| Database | Oracle 19c (19.33) 2-node RAC, OCI DB System, us-phoenix-1; CDB `RACDB`, PDB `XSTRPDB` |
| Connector | Confluent Cloud Oracle Database Source, `tasks.max=1`, `mode=incrementing`, `poll.interval.ms=5000`, JSON_SR, one table (`ORDERMGMT.ORDERS`) read through a query |
| Connector user | Dedicated local PDB user with `SELECT` on the table |
| Service | PDB service registered on **both** instances (except JB7) |
| Path | Confluent Cloud, Egress Access Point, Azure Application Gateway TCP 1521 with both node VIPs, site-to-site VPN, OCI DRG |
| Other connectors | The XStream connector was paused and the LogMiner connector was running during these tests |

### Method

Same as the other connector tests: a producer on a surviving node inserted a uniquely tagged row about every 2 s, a kcat consumer on an Azure VM matched rows by tag, and a sampler recorded the connector status and the connector's database sessions every 15 s. Node actions used the OCI CLI (`stop`/`start` are graceful OS shutdowns, `reset` is an abrupt power cycle). No manual recovery was performed in any scenario.

## Findings

### 1. Node loss is a non-event for polling

The connector opens its connection to the database through the gateway, polls with `SELECT`, and keeps no state in the database. When the node it uses goes away it reconnects through the gateway to the surviving node. The status never left RUNNING in JB3, JB4, JB6A or JB6B, and the worst gap in delivery was 50 s (a hard reset). In the XStream tests the same events left the outbound server disabled until someone repaired it.

### 2. Total outage: automatic recovery, same shape as LogMiner

In JB5 the status stayed RUNNING for the first minutes of the outage, went FAILED at 23:12:37, and was RUNNING again at 23:28:46 with no action from the operator. Both instances were OPEN at 23:17:20, so recovery took about 11 minutes. All 1350 rows inserted after the restart arrived, up to 643 s late. The XStream connector had not recovered from the same scenario after 55 minutes. Alert on lag, not only on the status field.

### 3. Lowest latency and a steady rate of delivery

Median latency was 5 s in every run, which is the poll interval. A burst of 20,000 rows at about 99 rows/s was fully delivered 2 s after the last insert. Latency is bounded below by `poll.interval.ms` and can be reduced by lowering it, at the price of more queries. Higher rates were not tested.

### 4. Incrementing mode silently skips rows with lower IDs

In incrementing mode the connector reads rows whose ID is **greater than the highest ID it has already read**. Rows inserted with a lower ID are never delivered, with no error. This happened in the test: a load test had inserted IDs from 50,000,000 and a producer with IDs near 1,500,000 was then ignored. Rows that are updated or deleted after being read are not captured at all, and two writers committing IDs out of order can lose rows. If IDs are not strictly increasing in commit order, use a timestamp column that is updated on every change (it must not be nullable, per Confluent's documentation) together with the incrementing column.

### 5. Control plane and status behaviour

- A configuration update is accepted by the CLI (`Updated connector`) even when the connector's validation then fails. Validation runs afterwards, and a failure leaves the connector running on its previous configuration. The reason is in the `trace` field of `confluent connect cluster describe -o json`. See finding 6.
- Configuration updates that passed validation restarted the task of a FAILED connector within about a minute in the tests. A running connector that keeps showing RUNNING after an update may simply have rejected it (finding 6), so after any update confirm in the database (`gv$session.service_name`) or in the connector logs that the task uses the new settings.
- Pause took 30 s on the one occasion it was tried.
- The connector's database session can be left behind for several minutes after a task is replaced.

### 6. A service on only one instance fails validation (JB7)

With a PDB service registered on one instance and both VIPs in the AppGW pool, the creation of a new connector and four consecutive configuration updates all failed validation with `SQLState 08006, errorCode 12514` (listener does not know the service), because the validation connection landed on the node without the service. The running connector kept its previous configuration and showed no problem. As a result, the first attempts at JB7 (a 15-minute run and forced session kills) never used the single-node service and were discarded. Whether the JDBC task itself can run against a service that exists on one node was therefore **not tested**. The requirement is the same as for the other connectors: register the service on every instance in the pool.

## Comparison

See [CONNECTOR-COMPARISON.md](../../oracle-rac/docs/CONNECTOR-COMPARISON.md) for the three connectors side by side.

## Limits of these results

- One run per scenario; timings are from single runs.
- A single table with an incrementing key was read; an `ORDER_ID` column of type `NUMBER` without precision had to be cast in a query (see [JDBC-SETUP.md](./JDBC-SETUP.md)).
- JB1 was run with the two producers one after the other to avoid ID collisions. An earlier baseline attempt produced rows with IDs below the connector's offset, which were never delivered (finding 4) and are excluded.
- JB6A and JB6B each had one producer insert time out while the survivor reconfigured; these are source-side effects and are not counted as inserted rows.
- The laptop that drove the tests slept for about 15 minutes during JB5's watch; row accounting comes from the consumer and is complete. The state sampler has a gap there.
- Graceful `stop` is an OS shutdown. Only JB6A and JB6B were abrupt.
- Snapshots of large tables, schema changes, LOB columns and update or delete capture were not tested.
- The throughput test reached about 99 rows/s only.

## Related documentation

- [JDBC-SETUP.md](./JDBC-SETUP.md): database and connector setup
- [CONNECTOR-COMPARISON.md](../../oracle-rac/docs/CONNECTOR-COMPARISON.md)
- [Shared gateway setup](../../oracle-rac/docs/APPGW-SETUP.md)
- [Repository README](../../oracle-rac/README.md)
