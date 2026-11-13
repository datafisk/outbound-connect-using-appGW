# Oracle RAC High Availability Testing: Oracle CDC Source Connector (LogMiner only)

> **Scope: this document covers the fully managed Oracle CDC Source connector (`OracleCdcSource`), which reads the redo log through Oracle LogMiner.** It does not apply to the XStream CDC connector ([HA-TESTING-XSTREAM.md](../../oracle-rac-xstream/docs/HA-TESTING-XSTREAM.md)) or the JDBC Source connector. Setup: [LOGMINER-SETUP.md](./LOGMINER-SETUP.md).

## Summary

The same 2-node Oracle RAC on OCI, the same Egress Access Point, Application Gateway (TCP listener, pool = both node VIPs) and the same failure scenarios as the XStream tests were used.

**Main result: the LogMiner connector rode through every node failure that was tested without manual action, and no rows were lost or duplicated in any scenario.** After a total outage of both nodes it recovered about 12 minutes after the database was back, with no intervention. A database service present on only one node did not break it. The cost is higher and less even latency (median about 9 s) and, after a total outage, a backlog that arrives late.

| # | Scenario | Connector status | Recovery | Rows in Kafka |
|---|----------|------------------|----------|---------------|
| LM1 | Baseline, inserts on both nodes | RUNNING | n/a | 28/28 (14 per node), each once |
| LM3 | Graceful stop of racnode2 (hosted the mining session), 3 min | RUNNING throughout | Mining session on instance 1 within about 20 s | 1169/1169, 0 dups, largest arrival gap 11 s |
| LM4 | Graceful stop of racnode1 (hosted the session), 3 min | RUNNING throughout | Session on instance 2 within about 30 s | 891/891, 0 dups, largest gap 20 s |
| LM6A | Hard reset (`oci db node reset`) of racnode2 (host) | RUNNING throughout | Sessions on instance 1 about 80 s after the reset | 1189/1189, 0 dups, largest gap 75 s, max latency 81 s |
| LM6B | Hard reset of racnode1 (host) | RUNNING throughout | Sessions on instance 2 about 100 s after the reset | 702/702, 0 dups, largest gap 95 s, max latency 68 s |
| LM5 | Both nodes stopped for 3 min, then started | RUNNING while the DB was down, FAILED 6 min into the outage, RUNNING again at 18:32:56 | **Automatic**, about 12 min after both instances were OPEN | 43/43 before; 992/992 after, 0 dups, max latency 656 s (backlog) |
| LM7 | Service on one instance only, both VIPs in the pool | RUNNING | Reconnect after forced session loss took about 5 min, then 23 s | 10/10 test rows, nothing lost |
| LM9 | `oracle.fan.events.enable=true` | RUNNING | n/a | 57/57, nothing lost |
| LM2 | Load: 20,000 rows at about 99 rows/s for 202 s | RUNNING | n/a | 20,000/20,000, 0 dups; median latency 9 s, p95 12 s, max 13 s; last row 11 s after the last insert |

## Test environment

| Item | Value |
|------|-------|
| Database | Oracle 19c (19.33) 2-node RAC, OCI DB System, us-phoenix-1; CDB `RACDB`, PDB `XSTRPDB`, ARCHIVELOG |
| Connector | Confluent Cloud Oracle CDC Source, `tasks.max=1`, `start.from=current`, JSON_SR key and value, FAN off unless stated |
| Connector user | Dedicated common user `C##CDCUSER` with the LogMiner role from [LOGMINER-SETUP.md](./LOGMINER-SETUP.md) |
| Service | CDB service that is registered on **both** instances (except LM7) |
| Path | Confluent Cloud, Egress Access Point, Azure Application Gateway TCP 1521 with both node VIPs, site-to-site VPN, OCI DRG |
| Other connectors | The XStream connector on the same database was paused during these tests (its database session can stay attached while paused, see [HA-TESTING-XSTREAM.md](../../oracle-rac-xstream/docs/HA-TESTING-XSTREAM.md)) |

### Method

Same as the XStream tests: a producer on a surviving node inserted a uniquely tagged row about every 2 s, a kcat consumer on an Azure VM (the cluster is private) matched rows by tag, and a sampler recorded the connector status and the database-side sessions every 15 s. Node actions used the OCI CLI (`stop`/`start` are graceful OS shutdowns, `reset` is an abrupt power cycle). Duplicates and missing rows are counted exactly from the tags. No manual recovery was performed in any scenario.

## Findings

### 1. Node loss is handled by reconnecting, with no database objects to repair

The connector keeps no server-side objects in the database. A mining session is an ordinary connection. When the instance holding it goes away, the connector opens new sessions through the gateway on the surviving instance and continues from its last committed SCN. In LM3, LM4, LM6A and LM6B the connector status never left RUNNING and nothing needed repair. This is the opposite of XStream, where the outbound server stays DISABLED until someone re-enables it.

### 2. Both redo threads are captured (LM1)

Rows inserted on racnode1 and racnode2 in the same period (14 each) all arrived exactly once. Run this first on any RAC that will be used.

### 3. Delivery is at-least-once in the documentation, but no duplicates were observed

The documentation states the connector may rewrite part of the redo log events after a restart. No duplicates occurred in any of these runs, including the full outage. Design consumers to tolerate duplicates anyway; the tests do not prove they cannot happen.

### 4. Total outage: automatic, but slow, and the status field misleads

In LM5 the status stayed RUNNING for the first minutes of the outage while the database was down, then went FAILED about 6 minutes into the outage. The database was back (both instances OPEN) at 18:20:53. The connector's sessions came back at about 18:31:40, and the status read RUNNING at 18:32:56. All 992 rows inserted after the restart arrived, up to 656 s late. For the same scenario XStream had not recovered after 55 minutes (HB8).

Alert on end-to-end lag, not only on the connector status: the status showed RUNNING while no data could flow, and FAILED while the connector was already reconnecting.

### 5. Latency is higher and steadier than XStream

Median end-to-end latency was 8 to 10 s in every run, with a p95 of 11 to 12 s. The XStream connector measured a median of 4.8 s in HB7. At about 99 rows/s the connector kept up with a 202 s burst, and the last row arrived 11 s after the last insert. Higher rates were not tested.

### 6. A service on only one instance does not break this connector (LM7)

With the service on one instance and both VIPs in the AppGW pool, one of two configuration updates was rejected and the other was accepted. The connector stayed RUNNING. After deliberately killing its database sessions, the first reconnect took about 5 minutes and the second 23 s (retries after hitting the node without the service), and rows kept flowing. For comparison, XStream was FAILED with `ORA-12514` in the same setup (HB11, HB12). Still register the service on every pooled node: the configuration validation failed for one of two attempts, and the extra reconnect time is avoidable.

### 7. `oracle.fan.events.enable` has no visible effect through the gateway (LM9)

The cluster's ONS daemon is running (remote port 6200, SSL), but the gateway forwards only port 1521, so FAN notifications cannot reach the connector. The setting was accepted and the connector worked normally. The connector documentation warns that enabling it on a database not set up for FAN can cause connection problems; none were seen here. Leave it off for this pattern.

## Comparison with the XStream connector

| | XStream (HA-TESTING-XSTREAM.md) | LogMiner (this document) |
|---|---------------------------------|--------------------------|
| Stop or reset of the node hosting the session | `XOUT` DISABLED in about 35 s, no unattended recovery (HB6, HB9); reset of a non-host node had no effect (HB10) | RUNNING throughout, sessions moved in 20 to 100 s |
| Both nodes down | No recovery in 55+ min | Automatic, about 12 min after the database returned |
| Manual recovery needed | Yes (`start_outbound`, pause/resume) | None needed in any test |
| Status vs reality | Can read RUNNING while stalled (HB9) | Can read RUNNING during an outage and FAILED while recovering (LM5) |
| Median latency | 4.8 s | 8 to 10 s |
| Service on one instance, both VIPs | Fails (`ORA-12514`) | Works, with slower reconnects |
| Database footprint | Capture, queue and outbound server | A dedicated user and read access to the redo log |
| Licensing (per Confluent docs) | No additional Oracle license for the Confluent connector | Not stated on the pages read; confirm |

## Limits of these results

- One run per scenario; timings are from single runs.
- Graceful `stop` is an OS shutdown. LM6A and LM6B are the abrupt cases.
- Mining-session placement was observed from database sessions, which are visible only part of the time, so placement times are approximate.
- Sampling gaps: LM3 (about 3 minutes) and LM6A (about 18 minutes, laptop asleep) have gaps in the state samples; row accounting comes from the consumer and is complete.
- In LM6A and LM6B some producer inserts failed (one timeout while the survivor was reconfiguring, and ID collisions caused by a leftover producer process). These are test artifacts and are excluded from the counts.
- The prerequisite readiness scripts supplied by Confluent were not run; privileges were verified by logging in as the connector user and reading the required views.
- The XStream connector was paused during these tests; running both at once was not measured.
- `tasks.max=1`, `start.from=current`; the snapshot phase, LOB columns, DDL changes and long-running transactions were not tested.
- Only the Confluent Cloud connector was tested, in this one environment (Azure to OCI). The throughput test went up to about 99 rows/s only.

## Related documentation

- [LOGMINER-SETUP.md](./LOGMINER-SETUP.md): database and connector setup
- [HA-TESTING-XSTREAM.md](../../oracle-rac-xstream/docs/HA-TESTING-XSTREAM.md): XStream results
- [APPGW-SETUP.md](../../oracle-rac/docs/APPGW-SETUP.md): Application Gateway configuration
- [Repository README](../../oracle-rac/README.md)
