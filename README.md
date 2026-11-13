# Confluent Cloud Connector Patterns for Azure

Tested reference setups for connecting Confluent Cloud fully managed connectors to databases and brokers over private networking on Azure (Egress Access Points, Application Gateway, Private Link), with a focus on high availability and failover.

Everything specific to a connector (architecture, setup, scripts, testing, troubleshooting) lives in that pattern's folder. Start with its README.

## Patterns

| Pattern | What it covers |
|---------|----------------|
| [azure-sql-failover](./patterns/azure-sql-failover/) | Azure SQL failover groups: four connectivity options (public, restricted public, dual EAP, EAP + AppGW) |
| [ibm-mq](./patterns/ibm-mq/) | IBM MQ source with mutual TLS and AppGW idle-timeout/heartbeat alignment |
| [tableflow-azure](./patterns/tableflow-azure/) | Tableflow to ADLS Gen2 over Private Link via AppGW and NGINX or NGINXaaS SNI routing |
| [oracle-rac](./patterns/oracle-rac/) | Oracle RAC via AppGW, bypassing SCAN VIPs: shared gateway/egress setup, OCI Terraform, connector comparison |
| [oracle-rac-xstream](./patterns/oracle-rac-xstream/) | Oracle XStream CDC Source on RAC: setup and HA test results |
| [oracle-rac-logminer](./patterns/oracle-rac-logminer/) | Oracle CDC Source (LogMiner) on RAC: setup and HA test results |
| [oracle-rac-jdbc](./patterns/oracle-rac-jdbc/) | Oracle Database (JDBC) Source on RAC: setup and HA test results |

## Structure

```
patterns/
  <pattern>/
    README.md              overview, options, quick start
    terraform/             infrastructure (where applicable)
    connector-config/      connector templates and generators
    egress-access-points/  EAP / AppGW setup per approach
    scripts/               pattern automation
    docs/                  setup, testing, troubleshooting
  _template/               starting point for a new pattern
scripts/deploy-pattern.sh  guided deployment helper
```

## Adding a pattern

Copy `patterns/_template/` and follow [CONTRIBUTING.md](./CONTRIBUTING.md).

## Prerequisites

Azure CLI, Confluent CLI, Terraform, `jq`, and a Confluent Cloud cluster type that supports Egress Access Points.
