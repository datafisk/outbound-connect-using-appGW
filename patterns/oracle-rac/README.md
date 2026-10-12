# Oracle RAC (Real Application Clusters) Pattern

## TL;DR

Connect Confluent Cloud fully managed JDBC Source or XStream connectors to Oracle RAC clusters with high availability using Azure Application Gateway to bypass SCAN VIP limitations. AppGW load balances across RAC nodes directly, enabling automatic failover when nodes fail (~$150-180/month for AppGW + Oracle compute costs).

## Overview

This pattern demonstrates how to deploy Confluent Cloud fully managed connectors to Oracle Real Application Clusters (RAC) with:

- **High Availability**: Automatic failover across RAC nodes
- **SCAN VIP Bypass**: Direct connection to RAC node IPs via Application Gateway
- **XStream or JDBC**: Support for both connector types
- **Multi-Cloud**: Works with Oracle Cloud Infrastructure (OCI), Azure VMs, or on-premises RAC
- **Private Connectivity**: Via Confluent Egress Access Points

### The Challenge

Oracle RAC presents unique challenges for Confluent Cloud connectors:

1. **SCAN VIP Complexity**: RAC uses SCAN (Single Client Access Name) VIPs that round-robin DNS, but Confluent egress DNS doesn't support this pattern
2. **Node Failover**: Connectors must handle RAC node failures gracefully
3. **REMOTE_LISTENER Configuration**: Must use FQDNs, not IPs, but FQDNs don't resolve in Confluent egress without custom DNS entries
4. **Cross-Cloud Connectivity**: RAC often lives in OCI or on-premises, requiring network connectivity to Azure

### Architecture

```
┌──────────────────────────────────────────────────────────┐
│ Oracle RAC Cluster (OCI/Azure/On-Prem)                   │
│                                                           │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐        │
│  │ RAC Node 1 │  │ RAC Node 2 │  │ RAC Node 3 │        │
│  │ 10.99.1.108│  │ 10.99.1.29 │  │ 10.99.1.50 │        │
│  │ Port: 1521 │  │ Port: 1521 │  │ Port: 1521 │        │
│  └────────────┘  └────────────┘  └────────────┘        │
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
│  Backend Pool: [10.99.1.108, 10.99.1.29, 10.99.1.50]    │
│  Load Balancing: Least Connections                       │
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

### 2. Azure Virtual Machines

**Platform**: Oracle RAC on Azure VMs

Deploy Oracle RAC on Azure VMs (complex, not recommended for production):
- Requires manual Oracle installation and RAC configuration
- Shared storage setup (NFS or Azure NetApp Files)
- Only for testing/PoC

📁 See: [terraform/azure/](./terraform/azure/)

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

# Note the RAC node IPs from outputs
terraform output rac_node_ips
```

### Option 2: Use Existing RAC

If you have existing Oracle RAC:

1. **Get RAC node private IPs:**
```sql
-- On RAC, check node IPs
SELECT instance_name, host_name, version FROM v$instance;
```

2. **Configure REMOTE_LISTENER (CRITICAL):**
```sql
-- On EACH RAC node
ALTER SYSTEM SET REMOTE_LISTENER='racnode-scan.yourdomain.com:1521' SCOPE=BOTH;
ALTER SYSTEM REGISTER;

-- Verify (must be FQDN, not IPs)
SELECT name, value FROM v$parameter WHERE name = 'remote_listener';
```

### Configure Application Gateway

See [docs/APPGW-SETUP.md](./docs/APPGW-SETUP.md) or use the AppGW module:

```bash
cd egress-access-points/appgw-scan/

# Edit variables for your RAC node IPs
# Deploy AppGW backend configuration
terraform init
terraform apply
```

**Key AppGW Configuration:**
- Backend pool: All RAC node IPs
- Load balancing: **Least Connections** (best for RAC)
- Health probe: TCP port 1521
- Timeout: 60 seconds minimum

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

See [docs/XSTREAM-SETUP.md](./docs/XSTREAM-SETUP.md) for complete XStream configuration.

### Verify Connectivity

```bash
# From a VM in the same VNet as AppGW
nc -zv <appgw-ip> 1521

# Or using SQL*Plus
sqlplus jdbc_connector/<password>@<appgw-ip>:1521/<service_name>
```

## Testing High Availability

See [docs/HA-TESTING.md](./docs/HA-TESTING.md) for complete HA testing procedures.

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

3. **Verify connector continues:**
```bash
confluent connect cluster describe <connector-id>
# Should remain RUNNING
```

4. **Check AppGW routes to healthy node:**
```bash
az network application-gateway show-backend-health \
  --name <appgw-name> \
  --resource-group <rg>
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
- [docs/HA-TESTING.md](./docs/HA-TESTING.md) - High availability testing procedures
- [docs/XSTREAM-SETUP.md](./docs/XSTREAM-SETUP.md) - XStream CDC connector setup
- [docs/SINGLE-INSTANCE-FINDINGS.md](./docs/SINGLE-INSTANCE-FINDINGS.md) - Single-instance RAC analysis
- [docs/TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md) - Common issues

## Key Learnings

### REMOTE_LISTENER Must Use FQDNs, Not IPs

Oracle RAC's `REMOTE_LISTENER` parameter **must** be set to FQDNs (like `racnode-scan.domain.com:1521`), not IP addresses.

**Why this matters**: RAC nodes register themselves with the REMOTE_LISTENER. When services query the listener, Oracle returns the `REMOTE_LISTENER` value. If this is an IP, connections work. If it's an FQDN that doesn't resolve (like in Confluent egress), connections fail.

**Solution**: Application Gateway bypasses this by connecting directly to node IPs, avoiding REMOTE_LISTENER entirely.

### SCAN VIPs Don't Work with Confluent Egress

Oracle's SCAN (Single Client Access Name) uses round-robin DNS to distribute connections across RAC nodes. Confluent egress DNS doesn't support this pattern.

**Solution**: Application Gateway load balances directly to node IPs using health probes, providing the same effect as SCAN.

### Use "Least Connections" Load Balancing

Oracle RAC connections are long-lived. Round-robin load balancing can create imbalances as some connections stay active while others close.

**Solution**: AppGW's "Least Connections" algorithm ensures even distribution of active connections.

### Single-Instance RAC is Viable for Testing

You can run a "RAC" cluster with just one node for development/testing. This simplifies infrastructure while maintaining the same connection patterns.

See [docs/SINGLE-INSTANCE-FINDINGS.md](./docs/SINGLE-INSTANCE-FINDINGS.md) for details.

### ORA-12514 During Failover

When a RAC node fails, active connections may get `ORA-12514: TNS:listener does not currently know of service requested`.

**Cause**: Application tried to reconnect to failed node before AppGW health probe removed it.

**Solution**: Configure AppGW health probe with faster intervals (5-10 seconds) and connector retry logic.

## Known Limitations

1. **REMOTE_LISTENER FQDN Requirement**: Must be configured but creates DNS resolution challenges
2. **Cross-Cloud Networking**: Requires VPN/ExpressRoute/FastConnect setup
3. **Oracle Licensing**: Ensure proper licensing for multi-cloud deployment
4. **XStream Limitations**: Requires Oracle 11g or later with XStream license

## Automation Scripts

### deploy-oci-rac.sh

Deploys complete Oracle RAC on OCI:
```bash
cd terraform/oci/
./deploy-oci-rac.sh
```

### configure-appgw.sh

Configures AppGW for RAC:
```bash
cd egress-access-points/appgw-scan/
./configure-appgw.sh <rac-node-ips>
```

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
