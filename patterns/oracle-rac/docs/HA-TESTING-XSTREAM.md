# Oracle RAC High Availability Testing: XStream CDC Connector (XStream only)

> **Scope: this document covers the Oracle XStream CDC Source connector only.** It does not apply to the Oracle JDBC Source connector, which behaves differently (it polls and reconnects per query, with no long-lived outbound-server session tied to an instance). JDBC results, if and when tested, belong in a separate `HA-TESTING-JDBC.md`. Earlier JDBC observations are not repeated here.

## Summary

Tested the Confluent Cloud fully managed **Oracle XStream CDC Source** connector against a 2-node Oracle RAC on OCI, reached through an Egress Access Point and an Azure Application Gateway (L4 TCP listener, backend pool = the two node VIPs).

**Main result: the data path survives node failures, the connector does not always.** No rows were lost in any test that measured delivery (every inserted row reached Kafka, no duplicates), but in 3 of the 5 node-failure scenarios (HB6, HB8, HB9) the XStream outbound server stopped and either the connector sat idle or it failed. In those cases it did **not** recover on its own within the observation window (12 to 63 minutes). Recovery needed a database-side command plus a connector pause/resume. The two configuration scenarios (HB11, HB12) show that a database service present on only one RAC node breaks the connector when the gateway pool contains both VIPs.

| # | Scenario | Connector during/after | XStream `XOUT` | Auto-recovery | Rows in Kafka |
|---|----------|------------------------|----------------|---------------|---------------|
| HB6 | Graceful stop of node 1 (inferred to host the outbound server) | FAILED | DISABLED after 32 s | **No** (63 min watched) | 2629/2629 after manual recovery |
| HB7 | Graceful stop of node 2 (hosted only the queue service) | RUNNING throughout | ATTACHED | n/a (no failure) | 934/934 |
| HB8 | Both nodes stopped, then started | FAILED | DISABLED | **No** (55+ min watched) | 43/43 pre-outage, rest after manual recovery |
| HB9 | Graceful stop of node 2 when it hosted XStream | RUNNING (**silent stall**) | DISABLED after 35 s | **No** (12 min watched, then manual) | 1286/1286 after manual recovery |
| HB10 | Abrupt power cycle (`oci db node reset`) of node 2 | RUNNING throughout | ATTACHED | n/a (no failure) | 1940/1940 |
| HB11 | Service registered on one instance only | Config validation fails (ORA-12514) | unchanged | n/a | 2536/2536 |
| HB12 | RAC One Node emulation: service on one instance, both VIPs in pool | FAILED on reconnect (ORA-12514), no recovery in 9 min | DETACHED | **No** | not measured (node stop not run) |

Whether a node failure hurts depends on **which instance hosts the XStream capture and outbound-server session at that moment**, not on whether the failure is graceful or abrupt.

## Test environment

| Item | Value |
|------|-------|
| Database | Oracle 19c (19.33) 2-node RAC, OCI DB System, VM.Standard2.4, us-phoenix-1 |
| Instances | RACDB1 (racnode1), RACDB2 (racnode2); PDB `XSTRPDB` |
| Service used by the connector | CDB service `RACDB_dct_phx.<subnet>.<vcn>.oraclevcn.com`, **running on both instances** |
| XStream | Outbound server `XOUT`, capture `CAP$_XOUT_1`, queue service `Q$_XOUT_2`, user `C##GGADMIN`, tables `ORDERMGMT.{ORDERS,ORDER_ITEMS,CUSTOMERS,PRODUCTS}` |
| Path | Confluent Cloud, Egress Access Point, Azure Application Gateway (TCP listener 1521), site-to-site VPN into an OCI DRG, node VIPs |
| AppGW pool | Both node VIPs (never the SCAN VIP, never the node host IPs) |
| Confluent | Dedicated cluster, private networking, one XStream connector task |

### Method

- A producer on a **surviving** node inserted a row every second into `ORDERMGMT.ORDERS` with a unique tag. Rows were counted per test, so loss and duplicates can be measured exactly.
- A consumer (kcat on an Azure VM, because the cluster is private) read `RACDB.ORDERMGMT.ORDERS` for the whole session. Rows were matched by tag.
- A sampler recorded every 15 s: connector status and task state (Confluent CLI) plus `dba_xstream_outbound.status` (SQL on the surviving node).
- Node actions used the OCI CLI: `oci db node stop` (graceful OS shutdown, node unreachable about 15 s after the request), `oci db node reset` (abrupt power cycle), `oci db node start`.
- Unattended watch periods were 30 to 63 minutes. "No auto-recovery" means no recovery within that window, not never.

## Findings

### 1. XStream failure depends on where the outbound server runs, not on how the node dies

XStream places the capture process, the outbound server and the client session on one instance, and the queue service (`Q$_XOUT_n`) may run on another. After restarts the placement moves.

- HB6, HB8 and HB9 took down the instance that hosted the outbound server (confirmed for HB9's setup, inferred from the outcome for HB6 and HB8): `XOUT` went DISABLED within about 35 s.
- HB7 took down the instance that hosted only the queue service. No impact beyond a 34 s stall of the data flow shortly after the node came back.
- HB10, an abrupt power cycle, did not break XStream at all, which indicates the capture and outbound session was on the surviving instance. This is inferred from the outcome; the placement before that test was not captured.

Before any planned maintenance, check where XStream runs:

```sql
SELECT inst_id, name FROM gv$active_services WHERE name LIKE '%XOUT%';
SELECT inst_id, program FROM gv$session WHERE username = 'C##GGADMIN' AND type = 'USER';
SELECT status FROM dba_xstream_outbound;
```

### 2. Recovery is manual: re-enable the outbound server, then restart the connector task

When the outbound server is DISABLED it does not come back by itself, even with both instances healthy.

```sql
-- as SYSDBA on any open instance
EXEC dbms_xstream_adm.start_outbound(server_name => 'XOUT');
-- status moves to DETACHED, then ATTACHED once the connector reconnects
```

Then restart the connector task:

```bash
confluent connect cluster pause  <connector-id> --cluster <lkc> --environment <env>
# wait until the DB session of C##GGADMIN is gone (see finding 4), then
confluent connect cluster resume <connector-id> --cluster <lkc> --environment <env>
```

After recovery the backlog drained within about 30 s to 1 minute (HB6: 2629 rows; HB9: 764 rows up to 27 minutes old, drained at once). Nothing was lost because XStream resumes from its last processed position.

### 3. Connector status can say RUNNING while nothing flows

In HB9 the connector showed `RUNNING` with task `RUNNING` for more than 12 minutes while `XOUT` was DISABLED and no rows were delivered. Alert on **XStream status and end-to-end lag**, not on connector status alone:

```sql
SELECT server_name, status FROM dba_xstream_outbound;   -- expect ATTACHED
```

### 4. The Confluent control plane is slow and has sharp edges

Observed during recovery:

- Updating the connector configuration did **not** restart the task in one run (12 minutes watched, HB8) but did restart it within about 20 s in two later runs (HB12, valid config applied to a running connector and to a FAILED one). Treat it as unreliable and verify the DB session. Pause/resume always restarts it, but slowly.
- Pause took anywhere from 30 s to about 24 minutes to apply.
- A `resume` sent before the pause had actually taken effect was ignored.
- While the connector shows PAUSED the XStream session on the database can stay attached for hours. That session was a **live task** in HB12, not an orphan: killing it (`ALTER SYSTEM KILL SESSION`) made the connector FAILED with `ORA-00028`. Resume sent while the old session is still there is ignored. Do not kill the session; wait, or restart through resume.
- A configuration that fails validation is stored but not applied; the connector keeps running on the previous configuration.

### 5. Single-instance service does not work (HB11)

Connector config validation connects through the Application Gateway. With the service registered on one instance only and both VIPs in the pool, roughly half of the validation connections land on the other node and fail with `ORA-12514: listener does not currently know of service`. Five consecutive configuration updates failed this way and none applied. This confirms the requirement in this pattern: **register the connector service on every instance that is in the AppGW pool.**

The AppGW TCP probe cannot detect this condition (it only tests that the port accepts a connection), and `az network application-gateway show-backend-health` returns nothing for TCP pools.

### 6. Short outages inside the tests

| Event | Observed |
|-------|----------|
| Node stop to node unreachable | about 15 s |
| VIP relocation to the surviving node | within about 1 minute (`crsctl`/`srvctl` view from the survivor) |
| Hard reset, node back at OS level | about 3 minutes; both instances OPEN right after |
| Rows delivered during HB7 | median latency 4.8 s, one 34 s stall |

## Network issue found during testing: overlapping prefix

Intermittent `ORA-12170` and lost flows to one VIP were caused by the OCI prefix `10.99.0.0/16` also being listed on a second site-to-site connection (a GCP local network gateway) on the same Azure hub gateway. Traffic to 10.99.x.x was then load shared or misrouted across two tunnels. Removing the overlapping prefix from the unrelated connection fixed direct VM to VIP reachability (100%).

If a connector fails sporadically on only some connections, test each backend directly from a VM in the AppGW subnet before blaming Oracle or the connector.

Open item: raw TCP connects through the Application Gateway still failed about half of the time from a test VM after the overlap was removed, while the connector worked. Cause not determined.

## Single-node deployments

### Single-instance RAC (one node, one VIP)

Not tested as a separate scenario. Expected, inferred from the results above: the AppGW pool holds one backend (the VIP), the HB11 problem cannot occur, and the service must be registered on that node. There is no surviving node, so any node outage is a full outage and a restart is likely to leave `XOUT` DISABLED as in HB8, so the manual recovery steps apply.

### RAC One Node (HB12, emulated)

RAC One Node runs the instance on one node at a time and relocates it, so the database service exists on one node at a time. A true RAC One Node database was not available, so this was emulated on the 2-node RAC with an admin-managed service `xstron1` (preferred RACDB2, available RACDB1), which gives the same single-active-node behaviour for connections.

| Step | Pool | Result |
|------|------|--------|
| 1. Point the connector at `xstron1` | VIP2 only (the active node) | Config validation passed. The task restarted within about 20 s and attached through the gateway. XStream's capture and outbound server moved to the node that hosts the service. |
| 2. Add VIP1 back to the pool (both VIPs) | both VIPs | Existing sessions were dropped by the pool update (`ORA-03113`/`ORA-03114`). Reconnects landed on VIP1 about half of the time and failed with `ORA-12514` (service not on that node). The connector went FAILED within 30 s and did **not** recover on its own in 9 minutes. |
| 3. Pause, then resume | both VIPs | Pause took about 24 minutes to apply. The resume applied about 14 minutes later and the connector went straight back to FAILED with `ORA-12514`. |
| 4. Restore the original service (on both instances) | both VIPs | Config update restarted the task, RUNNING and ATTACHED about 90 s later. |

Conclusions:
- With a service on one node, **a pool containing both VIPs does not work**, not only for config validation (HB11) but for every reconnect. The XStream connector gives up after a fixed number of retries, and the gateway's TCP probe cannot see a missing service.
- **Use a pool with only the active node's VIP.** After a relocation or failover the pool must be changed to the new node's VIP. That pool change drops the connections, so plan for a connector restart. This operator procedure was **not tested through an actual node failure**; the planned node stop (HB12) was aborted before it ran because the pool change had already put the connector into FAILED.
- Plain 2-node RAC with the service on both nodes (the pattern's main design) is not affected.

## Recommendations

1. Register the connector database service on **all** RAC instances in the AppGW pool; use the node **VIPs** as backends.
2. Monitor `dba_xstream_outbound.status` and end-to-end lag. Alert on anything other than `ATTACHED`. Do not rely on connector status.
3. Write down the recovery runbook above (re-enable `XOUT`, wait for the old DB session to clear, pause, resume) and test it in your environment.
4. After any RAC restart, plan for a manual check of XStream status. Do not assume the connector self-heals.
5. Rebooting the node that hosts the XStream session will interrupt replication; schedule maintenance accordingly and drain that node last.
6. Keep prefixes unique across all connections that share the Azure hub gateway.

## Limits of these results

- One run per scenario. Timings are from single runs.
- The first two attempts at "node 1 failure" actually stopped node 2 because of a script bug (discovered through the OCI audit log). Those results were discarded and the scenario was rerun as HB6.
- XStream placement was recorded before HB7 only (the pre-test query for the other runs failed on shell escaping). Placement for HB6, HB8 and HB10 is inferred from the outcome.
- Graceful stop (`oci db node stop`) is an OS shutdown, so the database shuts down cleanly. Only HB10 was an abrupt failure.
- Unattended recovery was observed for at most 63 minutes.
- The earlier JDBC Source connector observations (VIP failover with zero downtime, auto-recovery about 6 minutes after a full cluster restart) came from a previous run with status polling only and have not been repeated with the same measurement here. The JDBC connector reconnects per poll, so it is less sensitive to outbound-server placement than XStream.

## Related documentation

- [XSTREAM-SETUP.md](./XSTREAM-SETUP.md): database and connector setup, including the RAC walk-through
- [APPGW-SETUP.md](./APPGW-SETUP.md): Application Gateway configuration
- [SINGLE-INSTANCE-FINDINGS.md](./SINGLE-INSTANCE-FINDINGS.md)
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
- [Repository README](../README.md)
