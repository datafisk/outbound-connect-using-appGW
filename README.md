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
- ✅ **Support for existing Azure Resource Groups, VNets, and Subnets**
- ✅ **Support for existing Confluent Cloud Networks and Attachments**
- ✅ Network Security Groups with required rules
- ✅ **Automated Confluent Cloud egress endpoint provisioning**
- ✅ Private Link Service for Confluent Cloud integration
- ✅ Example IBM MQ Source connector configuration
- ✅ Flexible backend pool configuration
- ✅ Production-ready security settings
- ✅ Public IP blocked from all incoming traffic

## ⚠️ Important Note: TCP/TLS Proxy Configuration

**As of March 18, 2026**, the Terraform azurerm provider (v4.64.0) does not yet support configuring TCP/TLS proxy settings for Application Gateway via code. While Azure Application Gateway Standard v2 fully supports TCP/TLS proxy for non-HTTP protocols like IBM MQ, you'll need to complete two manual configuration steps via Azure Portal after deployment:

1. Change health probe protocol from `Http` to `Tcp`
2. Change backend settings protocol from `Http` to `Https`

**See [TCP-PROXY-SETUP.md](TCP-PROXY-SETUP.md) for detailed instructions** (takes ~2 minutes via Azure Portal).

This limitation is only in the Terraform provider - the Azure platform itself fully supports TCP/TLS proxy capabilities.

## Quick Start

1. **Prerequisites**: Azure CLI (logged in) and Terraform 1.3+

2. **Configure Confluent Cloud Credentials**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your Confluent Cloud API keys and Azure subscription
   ```
   See [CONFLUENT-SETUP.md](CONFLUENT-SETUP.md) for detailed credential setup.

3. **Deploy** (creates both Azure and Confluent Cloud resources):
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Approve Private Link** (if needed):
   - Azure Portal → Application Gateway → Private Link Center → Approve

5. **Configure TCP/TLS Proxy** (manual step):
   - See [TCP-PROXY-SETUP.md](TCP-PROXY-SETUP.md) (~2 minutes)

6. **Configure Connector Variables**:
   ```bash
   cp connectors/ibm-mq-source.env.example connectors/ibm-mq-source.env
   # Edit connectors/ibm-mq-source.env with your values
   ```

7. **Deploy Connector**:
   ```bash
   cd connectors && ./generate-config.sh
   # Deploy the generated configuration to Confluent Cloud using the network ID from terraform output
   ```

## What's Included

- `main.tf` - Core Azure infrastructure (VNet, App Gateway, Private Link)
- `confluent.tf` - **Confluent Cloud egress endpoint automation** ⭐
- `variables.tf` - Customizable variables (Azure + Confluent)
- `outputs.tf` - Connection details and setup instructions
- `terraform.tfvars.example` - Example configuration with all required variables
- `CONFLUENT-SETUP.md` - **Confluent Cloud credential setup guide** ⭐
- `EXISTING-RESOURCES.md` - **Using existing Resource Groups/VNets/Subnets** ⭐
- `TCP-PROXY-SETUP.md` - **TCP/TLS proxy configuration guide** ⭐
- `connectors/ibm-mq-source.json` - IBM MQ connector template with variables
- `connectors/ibm-mq-source.env.example` - Example configuration values
- `connectors/generate-config.sh` - Script to generate final connector config
- `SETUP.md` - Detailed step-by-step guide

## Using Existing Resources

### Azure Resources

You can deploy into your existing Azure infrastructure:

```hcl
# terraform.tfvars
create_resource_group = false
existing_resource_group_name = "my-existing-rg"

create_vnet = false
existing_vnet_name = "my-vnet"

create_subnets = false
existing_appgw_subnet_name = "appgw-subnet"
existing_backend_subnet_name = "backend-subnet"
```

See [EXISTING-RESOURCES.md](EXISTING-RESOURCES.md) for complete guide including requirements and validation steps.

### Confluent Cloud Resources

You can use existing Confluent Cloud networks and attachments:

```hcl
# terraform.tfvars
# Use existing Confluent Cloud Network (CCN)
create_confluent_network = false
existing_confluent_network_id = "n-xxxxx"

# Optionally use existing Private Link Attachment
create_private_link_attachment = false
existing_private_link_attachment_id = "platt-xxxxx"
```

See [CONFLUENT-SETUP.md](CONFLUENT-SETUP.md) for details on when to use existing resources vs creating new ones.

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

**Note**: MQ credentials (username/password) are optional. If your IBM MQ server is configured to allow unauthenticated connections, you can leave these empty in the configuration. This is acceptable when relying on network-level security (Private Link, NSG, VPN), though using credentials provides defense-in-depth.

## Cost Estimate

- Application Gateway Standard_v2: ~$180-220/month (2 instances)
- Private Link Service: Minimal cost
- Data transfer: Based on usage

## Support

For issues or questions, see the detailed troubleshooting section in [SETUP.md](SETUP.md).
