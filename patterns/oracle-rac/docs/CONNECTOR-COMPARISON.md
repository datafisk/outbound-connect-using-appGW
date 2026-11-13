# Oracle RAC Connectors Compared: XStream, LogMiner and JDBC

The three fully managed Oracle source connectors were tested against the same 2-node Oracle RAC (OCI), Egress Access Point and Azure Application Gateway (TCP listener, pool = node VIPs), with the same failure scenarios. Every number below is from a single run; see each test document for the method and the limits.

| | XStream CDC | Oracle CDC (LogMiner) | Oracle Database (JDBC) |
|---|---|---|---|
| Folder | [oracle-rac-xstream](../../oracle-rac-xstream/README.md) | [oracle-rac-logminer](../../oracle-rac-logminer/README.md) | [oracle-rac-jdbc](../../oracle-rac-jdbc/README.md) |
| Mechanism | Outbound server streams changes | Reads the redo log through LogMiner | Polls tables with SQL |
| Captures deletes and every change | Yes | Yes | No |
| Database footprint | Capture, queue and outbound server | A user with read access to the redo log | A `SELECT`-only user |
| Median latency | 4.8 s | 8 to 10 s | 5 s (poll interval) |
| Throughput tested | Not tested | 20,000 rows at 99 rows/s, last row 11 s behind | 20,000 rows at 99 rows/s, last row 2 s behind |
| Stop or reset of the node holding the session | `XOUT` DISABLED, **no unattended recovery** (12 to 63 min watched) | RUNNING throughout, session moved in 20 to 100 s | RUNNING throughout, session moved in about 1 to 1.5 min |
| Both nodes down | No recovery in 55+ min | Automatic, about 12 min after the database returned | Automatic, about 11 min after the database returned |
| Manual recovery needed | Yes (`start_outbound`, pause/resume) | None in any test | None in any test |
| Service on one node only, both VIPs in the pool | Fails (`ORA-12514`) | Kept working, slower reconnects | Config validation failed 5 of 5; task behaviour not tested |
| Largest delivery gap in node tests | Minutes (until repaired) | 11 to 95 s | 10 to 50 s |
| Rows lost or duplicated | None | None | None (valid runs) |
| Status field reliability | Can read RUNNING while stalled | Can read RUNNING during an outage and FAILED while recovering | Same as LogMiner |

## Choosing

| Need | Choice |
|------|--------|
| Deletes, full change history, before/after images | LogMiner or XStream |
| CDC with the best recovery behaviour on RAC in these tests | LogMiner |
| Lowest source load and simplest setup, inserts only (or updates with a non-nullable timestamp), seconds of latency | JDBC |
| Highest throughput and lowest CDC latency, and a team that can run the manual recovery | XStream (throughput not tested here) |

## Common to all three

- Pool the **node VIPs**, never the SCAN VIP, and register the connector's service on **every** pooled node.
- Alert on end-to-end lag. For every connector the status field misled at some point during an outage.
- Keep the OCI prefix unique across all site-to-site connections on the Azure hub gateway.
- The CLI reports `Updated connector` even when validation then fails; read the connector `trace`.

## Documents

- XStream: [setup](../../oracle-rac-xstream/docs/XSTREAM-SETUP.md), [HA results](../../oracle-rac-xstream/docs/HA-TESTING-XSTREAM.md)
- LogMiner: [setup](../../oracle-rac-logminer/docs/LOGMINER-SETUP.md), [HA results](../../oracle-rac-logminer/docs/HA-TESTING-LOGMINER.md)
- JDBC: [setup](../../oracle-rac-jdbc/docs/JDBC-SETUP.md), [HA results](../../oracle-rac-jdbc/docs/HA-TESTING-JDBC.md)
