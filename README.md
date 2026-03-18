# Azure Application Gateway with Private Link for Confluent Cloud

This repository provides Terraform infrastructure as code to deploy an Azure Application Gateway (Standard v2) configured with Private Link support for Confluent Cloud fully managed connectors.

## Overview

Enable Confluent Cloud managed connectors to securely access private resources (databases, message queues, APIs) in Azure through Private Link and Application Gateway.

### Architecture

```
Confluent Cloud Managed Connector
    ↓ (Outbound Private Link)
Azure Private Link Service
    ↓
Application Gateway (Standard v2)
    ↓
Backend Resources (IBM MQ, SQL, APIs, etc.)
```

## Features

- ✅ Azure Application Gateway Standard v2 with Private Link configuration
- ✅ Complete VNet setup with dedicated subnets
- ✅ Network Security Groups with required rules
- ✅ Private Link Service for Confluent Cloud integration
- ✅ Example IBM MQ Source connector configuration
- ✅ Flexible backend pool configuration
- ✅ Production-ready security settings

## ⚠️ Important Note: TCP/TLS Proxy Configuration

**As of March 18, 2026**, the Terraform azurerm provider (v4.64.0) does not yet support configuring TCP/TLS proxy settings for Application Gateway via code. While Azure Application Gateway Standard v2 fully supports TCP/TLS proxy for non-HTTP protocols like IBM MQ, you'll need to complete two manual configuration steps via Azure Portal after deployment:

1. Change health probe protocol from `Http` to `Tcp`
2. Change backend settings protocol from `Http` to `Https`

**See [TCP-PROXY-SETUP.md](TCP-PROXY-SETUP.md) for detailed instructions** (takes ~2 minutes via Azure Portal).

This limitation is only in the Terraform provider - the Azure platform itself fully supports TCP/TLS proxy capabilities.

## Quick Start

1. **Prerequisites**: Azure CLI (logged in) and Terraform 1.3+

2. **Deploy**:
   ```bash
   chmod +x deploy.sh
   ./deploy.sh
   ```

3. **Configure Confluent Cloud**: Use the Private Link Service Alias from the output

4. **Configure Connector Variables**:
   ```bash
   cp connectors/ibm-mq-source.env.example connectors/ibm-mq-source.env
   # Edit connectors/ibm-mq-source.env with your values
   ```

5. **Deploy Connector**:
   ```bash
   cd connectors && ./generate-config.sh
   # Deploy the generated configuration to Confluent Cloud
   ```

## What's Included

- `main.tf` - Core infrastructure (VNet, App Gateway, Private Link Service)
- `variables.tf` - Customizable variables
- `outputs.tf` - Important values for Confluent Cloud setup
- `TCP-PROXY-SETUP.md` - **TCP/TLS proxy configuration guide** ⭐
- `connectors/ibm-mq-source.json` - IBM MQ connector template with variables
- `connectors/ibm-mq-source.env.example` - Example configuration values
- `connectors/generate-config.sh` - Script to generate final connector config
- `deploy.sh` - Automated infrastructure deployment script
- `SETUP.md` - Detailed step-by-step guide

## Documentation

See [SETUP.md](SETUP.md) for detailed deployment and configuration instructions.

## Example Connector

Included example: **IBM MQ Source Connector** that reads messages from IBM MQ and publishes to Kafka topics via Private Link.

### Connector Configuration

The connector uses a variable-based configuration system:
- `ibm-mq-source.json` - Template with variable placeholders
- `ibm-mq-source.env.example` - Example values for all variables
- `generate-config.sh` - Generates final config with values substituted

All MQ and JMS parameters are configurable via environment variables for security and flexibility.

## Cost Estimate

- Application Gateway Standard_v2: ~$180-220/month (2 instances)
- Private Link Service: Minimal cost
- Data transfer: Based on usage

## Support

For issues or questions, see the detailed troubleshooting section in [SETUP.md](SETUP.md).
