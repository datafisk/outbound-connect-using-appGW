# IBM MQ Source Connector Pattern

## TL;DR

Connect Confluent Cloud fully managed source connectors to IBM MQ with mutual TLS authentication and long-lived connection handling. Uses Azure Application Gateway with properly configured idle timeouts to prevent connection drops during queue inactivity (~$150-180/month for AppGW + compute costs).

## Overview

This pattern demonstrates how to deploy a Confluent Cloud fully managed IBM MQ Source connector with:

- **Mutual TLS authentication** using self-signed certificates
- **Long-lived connection handling** via Azure Application Gateway
- **Heartbeat configuration** to prevent idle timeout connection drops
- **Private connectivity** via Confluent Egress Access Points

### The Challenge

IBM MQ connections require:

1. **Mutual TLS Authentication**: Both server and client certificates for secure communication
2. **Long-lived Connections**: MQ connections can remain idle for extended periods when queues are empty
3. **Idle Timeout Management**: Application Gateways will close idle connections, causing reconnection storms

### Architecture

```
┌─────────────────────────────────────────┐
│ IBM MQ Server (Ubuntu/Container)        │
│                                         │
│  Queue Manager: QM1                    │
│  Channel: CONFLUENT.CHL (SSL/TLS)      │
│  Queue: DEV.QUEUE.1                    │
│  Listener: 1414 (SSL)                  │
└─────────────────────────────────────────┘
              │
              │ Mutual TLS over Private Link
              ▼
┌─────────────────────────────────────────┐
│ Azure Application Gateway               │
│                                         │
│  Idle Timeout: 15 minutes              │
│  Backend Pool: IBM MQ Private Endpoint │
│  Health Probe: TCP 1414                │
└─────────────────────────────────────────┘
              │
              │ Private Link
              ▼
┌─────────────────────────────────────────┐
│ Confluent Cloud                         │
│                                         │
│  Egress Access Point → AppGW           │
│  IBM MQ Source Connector               │
│  Heartbeat Interval: 5 minutes         │
└─────────────────────────────────────────┘
```

## Components

- **IBM MQ Server**: Queue manager with mutual TLS enabled
- **Self-Signed CA**: Certificate authority for signing certificates
- **Azure Application Gateway**: Layer 7 load balancer with idle timeout management
- **Confluent Egress Access Point**: Private Link from Confluent to Azure
- **IBM MQ Source Connector**: Fully managed connector with heartbeat configuration

## Prerequisites

- IBM MQ installed on Ubuntu or running in container
- Azure subscription for Application Gateway
- Confluent Cloud Enterprise cluster (for EAP support)
- Azure CLI authenticated
- Confluent CLI authenticated
- Java `keytool` for certificate management
- IBM MQ `runmqakm` command (comes with MQ installation)

## Quick Start

### 1. Setup IBM MQ with Mutual TLS

```bash
cd scripts/

# Run setup script with your DNS domain
# IMPORTANT: Must match the DNS you'll configure in Confluent egress
./setup-mutual-tls.sh ibmmq.yourdomain.com

# This creates:
# - CA certificate and keystore
# - IBM MQ server certificate
# - Connector client certificate
# - Java keystores for connector
```

**Output files** in `ssl-certs/`:
- `connector-keystore.jks` - Client certificate keystore
- `connector-truststore.jks` - CA certificate truststore
- Keystore password: `<KEYSTORE_PASSWORD>`

### 2. Configure Application Gateway (Optional but Recommended)

If using Application Gateway for idle timeout management:

```bash
# See infrastructure/application-gateway/ for AppGW setup
# Or deploy manually via Azure Portal

# Key configuration:
# - Idle timeout: 15 minutes
# - Backend pool: IBM MQ private endpoint
# - Health probe: TCP port 1414
```

### 3. Upload Certificates to Confluent Cloud

```bash
cd ssl-certs/

# Base64 encode keystores
base64 connector-keystore.jks > connector-keystore.b64
base64 connector-truststore.jks > connector-truststore.b64

# Upload to your secrets manager or use directly in connector config
```

### 4. Configure and Deploy Connector

```bash
cd ../connector-config/

# Edit ibm-mq-source.env.example and save as ibm-mq-source.env
# Set your values:
# - MQ_QUEUE_MANAGER=QM1
# - MQ_HOSTNAME=<appgw-or-mq-hostname>
# - KAFKA_API_KEY / KAFKA_API_SECRET
# - Base64 encoded keystores

# Generate connector JSON
./generate-config.sh

# Create connector
confluent connect cluster create --config-file ibm-mq-source.generated.json
```

### 5. Test Message Flow

```bash
cd ../scripts/

# Generate test messages to MQ queue
./mq-message-generator.sh 10

# Verify messages appear in Kafka topic
confluent kafka topic consume ibm-mq-messages --from-beginning
```

## Critical Configuration: Heartbeat and Idle Timeout

To prevent connection drops during queue inactivity:

```
IBM MQ Heartbeat Interval < Application Gateway Idle Timeout
```

**Recommended Configuration:**
- **AppGW Idle Timeout**: 15 minutes (900 seconds)
- **MQ Client Heartbeat**: 5 minutes (300 seconds)

This ensures heartbeat traffic keeps the connection alive before the gateway timeout.

### Connector Configuration

In your connector config (`ibm-mq-source.json`):

```json
{
  "mq.client.reconnect.options": "QMGR",
  "mq.client.heartbeat.interval": "300",
  "jms.client.id": "confluent-mq-connector"
}
```

See [docs/HEARTBEAT-CONFIG.md](./docs/HEARTBEAT-CONFIG.md) for detailed configuration.

## Cost Analysis

### With Application Gateway

| Component | Monthly Cost |
|-----------|--------------|
| **Application Gateway (Standard_v2)** | $150-180 |
| **Private Endpoint** | $7 |
| **IBM MQ Compute** | $50-500 (depends on VM size) |
| **Data Transfer** | ~$5-10 |
| **Total** | **~$212-697/month** |

### Without Application Gateway

| Component | Monthly Cost |
|-----------|--------------|
| **Private Endpoint** | $7 |
| **IBM MQ Compute** | $50-500 |
| **Data Transfer** | ~$5-10 |
| **Total** | **~$62-517/month** |

**Note**: Without AppGW, you'll need to manage reconnections during idle periods or use public endpoints.

## Documentation

- [docs/SSL-TLS-SETUP.md](./docs/SSL-TLS-SETUP.md) - Complete SSL/TLS setup guide
- [docs/HEARTBEAT-CONFIG.md](./docs/HEARTBEAT-CONFIG.md) - Heartbeat and idle timeout configuration
- [docs/TCP-PROXY-SETUP.md](./docs/TCP-PROXY-SETUP.md) - TCP proxy setup for testing
- [docs/TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md) - Common issues and solutions

## Key Learnings

### Mutual TLS is Required for Production

IBM MQ best practices require mutual TLS authentication. Using channels without TLS is not recommended for production.

### Idle Timeout Alignment is Critical

Misaligned timeouts between MQ heartbeat and AppGW idle timeout cause:
- Connection drops during queue inactivity
- Reconnection storms
- Message processing delays
- Connector task failures

**Solution**: Set MQ heartbeat interval < AppGW idle timeout

### Certificate DNS Names Must Match

The certificate's CN (Common Name) or SAN (Subject Alternative Name) must match the hostname the connector uses to connect. Mismatch causes TLS handshake failures.

### Java Keystores vs PEM Files

Confluent connectors use Java keystores (`.jks` files), not PEM files. You must convert certificates to JKS format using `keytool`.

## Automation Scripts

### setup-mutual-tls.sh

Creates complete mutual TLS setup:
- Self-signed CA
- Server and client certificates
- MQ queue manager configuration
- Java keystores

Usage:
```bash
./scripts/setup-mutual-tls.sh <dns-domain>
```

### cleanup-mutual-tls.sh

Removes all TLS configuration and certificates:
```bash
./scripts/cleanup-mutual-tls.sh
```

### mq-message-generator.sh

Generates test messages to MQ queue:
```bash
./scripts/mq-message-generator.sh <number-of-messages>
```

## Troubleshooting

### Connection Refused

**Cause**: MQ listener not running or firewall blocking

**Solution**:
```bash
# Check MQ listener
sudo su - mqm
dspmq -m QM1
runmqsc QM1
DISPLAY LISTENER(SYSTEM.SSL.LISTENER.TCP)
```

### TLS Handshake Failed

**Cause**: Certificate mismatch or wrong keystore

**Solution**:
1. Verify certificate CN matches hostname
2. Check keystore password is correct
3. Verify truststore contains CA certificate

### Messages Not Flowing

**Cause**: Channel or queue configuration issue

**Solution**:
```bash
# Check channel status
echo "DISPLAY CHSTATUS(CONFLUENT.CHL)" | runmqsc QM1

# Check queue depth
echo "DISPLAY QLOCAL(DEV.QUEUE.1) CURDEPTH" | runmqsc QM1
```

### Connector Keeps Reconnecting

**Cause**: Idle timeout too low or heartbeat not configured

**Solution**: See [docs/HEARTBEAT-CONFIG.md](./docs/HEARTBEAT-CONFIG.md)

## Related Patterns

- [Azure SQL Failover](../azure-sql-failover/) - Similar private connectivity patterns
- [Oracle RAC](../oracle-rac/) - Another complex HA database setup

## References

- [IBM MQ Documentation](https://www.ibm.com/docs/en/ibm-mq)
- [Confluent IBM MQ Source Connector](https://docs.confluent.io/cloud/current/connectors/cc-ibm-mq-source.html)
- [Azure Application Gateway Documentation](https://docs.microsoft.com/azure/application-gateway/)

## Support

For issues or questions, see [docs/TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md) or open a GitHub issue.
