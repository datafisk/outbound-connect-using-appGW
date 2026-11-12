# Oracle RAC (Real Application Clusters) Pattern

## TL;DR

Connect Confluent Cloud fully managed JDBC Source or XStream connectors to Oracle RAC clusters with high availability using Azure Application Gateway to bypass SCAN listener redirects. AppGW load balances across the RAC node VIPs directly (~$150-180/month for AppGW + Oracle compute costs). XStream node-failure behaviour was tested on a 2-node RAC: no data loss, but recovery after some failures is manual (see [docs/HA-TESTING-XSTREAM.md](../oracle-rac-xstream/docs/HA-TESTING-XSTREAM.md)). The LogMiner-based Oracle CDC Source connector was tested in the same scenarios and recovered without manual action (see [docs/HA-TESTING-LOGMINER.md](../oracle-rac-logminer/docs/HA-TESTING-LOGMINER.md)).

## Overview

This pattern demonstrates how to deploy Confluent Cloud fully managed connectors to Oracle Real Application Clusters (RAC) with:

- **High Availability**: Automatic failover across RAC nodes
- **SCAN Bypass**: Direct connection to the RAC node VIPs via Application Gateway (no SCAN redirect)
- **XStream or JDBC**: Support for both connector types
- **Multi-Cloud**: Works with Oracle Cloud Infrastructure (OCI), Azure VMs, or on-premises RAC
- **Private Connectivity**: Via Confluent Egress Access Points

### The Challenge

Oracle RAC presents unique challenges for Confluent Cloud connectors:

1. **SCAN listener redirects**: A client connects to the SCAN name, and the SCAN listener answers with a TNS *redirect* to a node listener address (the VIP endpoint registered through `LOCAL_LISTENER`). The client then opens a second connection to that address. From Confluent Cloud that second hop fails: the redirect target is a private VIP or an Oracle-internal hostname that egress DNS can't resolve and the Egress Access Point can't reach. The AppGW is a Layer 4 TCP proxy, so it can't see or rewrite the redirect.
2. **Workaround**: Point the hostname the connector uses at the AppGW (egress DNS entry), and make the AppGW backend pool the **node VIPs**. The connector then talks straight to a node listener and the SCAN listener is never contacted.
3. **Service must exist on every node in the pool**: SCAN normally routes by service. The AppGW can't, and its TCP health probe can't detect a node without the service (`ORA-12514`).
4. **Node Failover**: Connectors must handle RAC node failures gracefully
5. **Cross-Cloud Connectivity**: RAC often lives in OCI or on-premises, requiring network connectivity to Azure

### Architecture

```
┌──────────────────────────────────────────────────────────┐
│ Oracle RAC Cluster (OCI/Azure/On-Prem)                   │
│                                                           │
│  ┌──────────────┐  ┌──────────────┐                     │
│  │ RAC Node 1   │  │ RAC Node 2   │                     │
│  │ <node1-ip>  │  │ <node2-ip>  │                     │
│  │ Port: 1521   │  │ Port: 1521   │                     │
│  └──────────────┘  └──────────────┘                     │
│                                                           │
│  SCAN VIP: racnode-scan.domain.com                       │
│  (Bypassed - not used by connector)                      │
└──────────────────────────────────────────────────────────┘
                     │
                     │ VPN / ExpressRoute / FastConnect
                     ▼
┌──────────────────────────────────────────────────────────┐
│ Azure Application Gateway                                 │
│                                                           │
│  Backend Pool: [<node1-vip>, <node2-vip>]               │
│  Health Probe: TCP port 1521                             │
│  Listener: TCP 1521                                      │
│  Private IP: 172.200.X.X                                 │
└──────────────────────────────────────────────────────────┘
                     │
                     │ Private Link
                     ▼
┌──────────────────────────────────────────────────────────┐
│ Confluent Cloud                                           │
│                                                           │
│  Egress Access Point → AppGW                             │
│  Connector: JDBC Source or XStream                       │
│  Connection: AppGW IP:1521                               │
└──────────────────────────────────────────────────────────┘
```

## Available Approaches

This pattern provides deployments for different environments:

### 1. Oracle Cloud Infrastructure (OCI)

**Platform**: Oracle RAC on OCI DB System

Deploy Oracle RAC natively on OCI and connect via:
- OCI FastConnect + Azure ExpressRoute
- Or VPN Gateway

📁 See: [terraform/oci/](./terraform/oci/)

### 2. Azure Virtual Machines (not viable)

**Platform**: Oracle RAC on self-managed Azure VMs

Not supported. We tried a 2-node Oracle Grid Infrastructure 19c install on Azure VMs. Azure has no multicast (worked around with a VXLAN overlay), but Grid Infrastructure 19c would only create a `STANDALONE` cluster or a `DOMAIN` cluster that needs GNS and DHCP control, which Azure doesn't provide. Multi-node RAC never formed. Details: [archive/oracle-rac-research/ORACLE-RAC-AZURE-FINDINGS.md](../../archive/oracle-rac-research/ORACLE-RAC-AZURE-FINDINGS.md).

Azure is still the right place for the **Application Gateway and Confluent egress**, with RAC itself on OCI or on-premises. [terraform/azure/](./terraform/azure/) is not an Azure RAC deployment: it deploys the Confluent Cloud connector with Terraform.

### 3. On-Premises RAC

**Platform**: Existing on-premises Oracle RAC

Connect to existing RAC via:
- Azure ExpressRoute to on-premises datacenter
- Site-to-Site VPN

Configuration same as OCI approach.

## Components

- **Oracle RAC Cluster**: 2-3 node cluster with shared storage
- **SCAN Listener**: Bypassed in this pattern
- **Application Gateway**: Layer 4 load balancer to RAC nodes
- **Confluent Egress Access Point**: Private Link from Confluent to Azure
- **Connector**: JDBC Source or XStream for CDC

## Prerequisites

- Oracle RAC cluster deployed (OCI, Azure, or on-premises)
- Network connectivity from Azure to RAC (VPN, ExpressRoute, FastConnect)
- Azure Application Gateway deployed or existing
- Confluent Cloud Enterprise cluster (for EAP support)
- Azure CLI authenticated
- Confluent CLI authenticated
- Terraform >= 1.0 (for infrastructure deployment)

## Quick Start

### Option 1: Deploy Oracle RAC on OCI

```bash
cd terraform/oci/

# Copy example vars
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values:
# - compartment_id (OCI compartment)
# - existing_vcn_id (VCN ID)
# - db_admin_password
# - etc.

# Deploy
terraform init
terraform apply

# The outputs list the VIP OCIDs (vip_ids), not the addresses. Get the VIP IPs from the
# OCI console (DB system > nodes) or on a node: srvctl config vip -node <node>
terraform output vip_ids
```

### Option 2: Use Existing RAC

If you have existing Oracle RAC:

1. **Get the RAC node VIPs** (not the SCAN addresses, not the node's physical IPs):
```bash
# As the grid user on a RAC node
srvctl config vip -node <node1>
srvctl config vip -node <node2>
```

2. **Check the service is registered on every node** and leave the listener parameters at their defaults:
```sql
-- LOCAL_LISTENER is the node VIP endpoint, REMOTE_LISTENER is the SCAN name:port. Do not change either.
SELECT inst_id, name, value FROM gv$parameter WHERE name IN ('local_listener','remote_listener');
SELECT inst_id, name FROM gv$active_services WHERE name NOT LIKE 'SYS%';
```
The service the connector uses must appear for **every** instance whose VIP is in the AppGW pool.

### Configure Application Gateway

See [docs/APPGW-SETUP.md](./docs/APPGW-SETUP.md), or add the route to an existing gateway with the script (dry run by default; it only adds objects and never replaces the gateway):

```bash
cd egress-access-points/appgw-scan/scripts
./setup.sh <appgw-rg> <appgw-name> 1521 <node1-vip> <node2-vip>           # prints the az commands
./setup.sh <appgw-rg> <appgw-name> 1521 <node1-vip> <node2-vip> --apply
```

**Key AppGW Configuration:**
- Listener: plain TCP (not TLS)
- Backend pool: all RAC node **VIPs**
- Health probe: TCP port 1521 (only checks the port, not the service)
- Idle timeout: 900 seconds (long-lived database connections)

### Deploy Connector

#### For JDBC Source Connector:

```bash
cd ../../connector-config/

# Create connector config
cat > oracle-jdbc-source.json <<EOF
{
  "name": "oracle-rac-jdbc-source",
  "config": {
    "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
    "connection.url": "jdbc:oracle:thin:@//<appgw-ip>:1521/<service_name>",
    "connection.user": "jdbc_connector",
    "connection.password": "<password>",
    "mode": "incrementing",
    "incrementing.column.name": "id",
    "topic.prefix": "oracle-rac-",
    "table.whitelist": "<schema>.<table>",
    "tasks.max": "1"
  }
}
EOF

# Create connector
confluent connect cluster create --config-file oracle-jdbc-source.json
```

#### For XStream (CDC) Connector:

See [docs/XSTREAM-SETUP.md](../oracle-rac-xstream/docs/XSTREAM-SETUP.md) for complete XStream configuration.

### Verify Connectivity

```bash
# From a VM in the same VNet as AppGW
nc -zv <appgw-ip> 1521

# Or using SQL*Plus
sqlplus jdbc_connector/<password>@<appgw-ip>:1521/<service_name>
```

## Connector options

The gateway, egress and RAC setup in this folder are shared. Each connector has its own folder with setup, test results and a connector template:

| Connector | Folder | Summary of the RAC test results |
|-----------|--------|---------------------------------|
| Oracle XStream CDC Source | [oracle-rac-xstream](../oracle-rac-xstream/README.md) | No data loss, but recovery after some node failures is manual |
| Oracle CDC Source (LogMiner) | [oracle-rac-logminer](../oracle-rac-logminer/README.md) | Recovered from every tested failure without manual action; higher latency |
| Oracle JDBC Source | [oracle-rac-jdbc](../oracle-rac-jdbc/) | In progress |

## Testing High Availability (XStream)

> The HA results in this repo are for the **XStream CDC connector only**, not the JDBC Source connector.

See [docs/HA-TESTING-XSTREAM.md](../oracle-rac-xstream/docs/HA-TESTING-XSTREAM.md) for complete HA testing procedures.

**Quick HA Test:**

1. **Verify initial state:**
```sql
SELECT instance_name, host_name, status FROM v$instance;
```

2. **Simulate node failure:**
```bash
# On one RAC node
sudo shutdown -h now
```

3. **Verify the connector and XStream:**
```bash
confluent connect cluster describe <connector-id>
```
```sql
SELECT status FROM dba_xstream_outbound;   -- expect ATTACHED
```
If the stopped node hosted the XStream outbound server, expect `DISABLED` and follow the recovery steps in [docs/HA-TESTING-XSTREAM.md](../oracle-rac-xstream/docs/HA-TESTING-XSTREAM.md).

4. **Check the AppGW still reaches a healthy node:**

`az network application-gateway show-backend-health` returns nothing for TCP pools, so test through the gateway instead, from a VM that can reach its private frontend IP:
```bash
sqlplus <user>/<password>@//<appgw-private-ip>:1521/<service_name>
# repeat a few times and check SELECT instance_name FROM v$instance;
```

## Cost Analysis

### With Oracle RAC on OCI

| Component | Monthly Cost |
|-----------|--------------|
| **OCI DB System (RAC, 2 nodes)** | $1,000-5,000 |
| **OCI FastConnect** | $215 (1 Gbps) |
| **Azure ExpressRoute** | $155 (1 Gbps) |
| **Application Gateway** | $150-180 |
| **Private Endpoint** | $7 |
| **Data Transfer** | ~$10-50 |
| **Total** | **~$1,537-5,607/month** |

### With Oracle RAC on Azure VMs

| Component | Monthly Cost |
|-----------|--------------|
| **Azure VMs (2-3 nodes, 8 vCPU)** | $600-900 |
| **Premium SSD (shared storage)** | $200-500 |
| **Oracle License (BYOL)** | $0 (if you own) |
| **Application Gateway** | $150-180 |
| **Private Endpoint** | $7 |
| **Total** | **~$957-1,587/month** |

**Note**: Azure VM approach is complex and not recommended for production.

### Without Application Gateway (Manual Failover)

Lower cost but requires manual intervention during RAC node failures.

## Documentation

- [docs/QUICKSTART.md](./docs/QUICKSTART.md) - Step-by-step deployment guide
- [docs/APPGW-SETUP.md](./docs/APPGW-SETUP.md) - Application Gateway configuration
- [docs/HA-TESTING-XSTREAM.md](../oracle-rac-xstream/docs/HA-TESTING-XSTREAM.md) - High availability testing procedures
- [docs/XSTREAM-SETUP.md](../oracle-rac-xstream/docs/XSTREAM-SETUP.md) - XStream CDC connector setup
- [docs/HA-TESTING-LOGMINER.md](../oracle-rac-logminer/docs/HA-TESTING-LOGMINER.md) - High availability testing, Oracle CDC Source (LogMiner) connector
- [docs/LOGMINER-SETUP.md](../oracle-rac-logminer/docs/LOGMINER-SETUP.md) - Oracle CDC Source (LogMiner) connector setup
- [docs/SINGLE-INSTANCE-FINDINGS.md](./docs/SINGLE-INSTANCE-FINDINGS.md) - Single-instance RAC analysis
- [docs/TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md) - Common issues

## Key Learnings

### SCAN Redirects Don't Work with Confluent Egress

The SCAN listener doesn't serve the session. It replies with a TNS redirect to a node listener address, and the client reconnects there. From Confluent Cloud that address (a node VIP or an Oracle-internal hostname) isn't resolvable or routable, so the connection fails.

**Solution**: Point the connector's hostname at the AppGW with a Confluent egress DNS entry, and use the node VIPs as the AppGW backend pool. The SCAN listener is never contacted, so there is no redirect. You give up SCAN's service-aware load balancing.

### REMOTE_LISTENER and LOCAL_LISTENER: Leave the Defaults

- `REMOTE_LISTENER` (normally `<scan-name>:1521`) only controls where instances register with the SCAN listeners. It is not part of the connector's path and does not need to change.
- `LOCAL_LISTENER` is the node VIP endpoint. It is what a SCAN redirect would hand to a client, and it is why the AppGW pool must use the **VIPs**: by default the node listener binds the VIP, not the physical IP.

Earlier versions of these docs said `REMOTE_LISTENER` must be an FQDN. That was not verified and is no longer a requirement.

### Load Balancing Across Nodes

The AppGW distributes new TCP connections across healthy backends. In the OCI retest, 10/10 connections through the gateway succeeded and landed on both RACDB1 and RACDB2. Connections are long-lived, so balance is only evaluated when a connection is opened.

### Single-Instance RAC is Viable for Testing

You can run a "RAC" cluster with just one node for development/testing. This simplifies infrastructure while maintaining the same connection patterns.

See [docs/SINGLE-INSTANCE-FINDINGS.md](./docs/SINGLE-INSTANCE-FINDINGS.md) for details.

### ORA-12514 During Failover

When a RAC node fails, active connections may get `ORA-12514: TNS:listener does not currently know of service requested`.

**Cause**: Application tried to reconnect to failed node before AppGW health probe removed it.

**Solution**: Configure AppGW health probe with faster intervals (5-10 seconds) and connector retry logic.

## Known Limitations

1. **Service on every pooled node**: The AppGW can't detect `ORA-12514` on a node that lacks the service. Use a uniform service, or put only nodes that carry it in the pool. See [docs/SINGLE-INSTANCE-FINDINGS.md](./docs/SINGLE-INSTANCE-FINDINGS.md).
2. **XStream recovery after a node failure can be manual**: If the instance hosting the XStream outbound server goes down, `XOUT` is DISABLED and the connector does not self-recover (observed for 55 to 63 min). Re-enable `XOUT`, then pause/resume the connector. No rows were lost. Connector status can read RUNNING while stalled, so monitor `dba_xstream_outbound.status`. See [docs/HA-TESTING-XSTREAM.md](../oracle-rac-xstream/docs/HA-TESTING-XSTREAM.md).
3. **TLS and hostname validation**: With TLS on the Oracle listener, the egress DNS name used in `connection.host` must be in the certificate the connector sees, or hostname validation must be disabled (less secure). Not tested in this repo. See [docs/APPGW-SETUP.md](./docs/APPGW-SETUP.md) step 3.3.
4. **Cross-Cloud Networking**: Requires VPN/ExpressRoute/FastConnect setup
5. **Oracle Licensing**: Ensure proper licensing for multi-cloud deployment
6. **XStream licensing and versions**: Confluent's documentation states that no additional Oracle license is needed to use XStream through the Confluent Cloud XStream CDC connector (covered by an agreement between Confluent and Oracle). Check the current [connector documentation](https://docs.confluent.io/cloud/current/connectors/cc-oracle-xstream-cdc-source/cc-oracle-xstream-cdc-source-features.html) for supported Oracle versions and terms. This pattern was tested on 19c.

## Automation

- [terraform/oci/](./terraform/oci/): deploys the 2-node RAC on OCI (`terraform apply`).
- [egress-access-points/appgw-scan/scripts/setup.sh](./egress-access-points/appgw-scan/scripts/setup.sh): adds the pool, probe, settings, listener and rule for the RAC nodes to an existing Application Gateway.
- [terraform/azure/](./terraform/azure/): deploys the Confluent Cloud connector with Terraform.

## Related Patterns

- [Azure SQL Failover](../azure-sql-failover/) - Similar HA database challenges
- [IBM MQ](../ibm-mq/) - Another complex HA setup with AppGW

## References

- [Oracle RAC Documentation](https://docs.oracle.com/en/database/oracle/oracle-database/19/racad/)
- [Confluent JDBC Source Connector](https://docs.confluent.io/cloud/current/connectors/cc-jdbc-source.html)
- [Confluent Oracle CDC Source (XStream)](https://docs.confluent.io/cloud/current/connectors/cc-oracle-cdc-source.html)
- [Azure Application Gateway](https://docs.microsoft.com/azure/application-gateway/)

## Support

For issues or questions, see [docs/TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md) or open a GitHub issue.
