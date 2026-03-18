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

This limitation is only in the Terraform provider - the Azure platform itself fully supports TCP/TLS proxy capabilities. Track the feature request here: [hashicorp/terraform-provider-azurerm#26239](https://github.com/hashicorp/terraform-provider-azurerm/issues/26239)

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

Included example: **IBM MQ Source Connector** that consumes messages from IBM MQ over Private Link (via Application Gateway) and produces to Kafka topics.

### IBM MQ Requirements

For the example configuration to work, your IBM MQ server must be configured with:

- **Port**: `1414` (standard IBM MQ listener port)
- **Queue Manager**: Named `QM1` (or update `MQ_QUEUE_MANAGER` in config)
- **Server Connection Channel**: Named `DEV.APP.SVRCONN` (or update `MQ_CHANNEL` in config)
- **Queue**: Named `DEV.QUEUE.1` (or update `JMS_DESTINATION_NAME` in config)
- **Transport Mode**: Client mode enabled
- **Network Access**: Reachable from the Application Gateway backend pool targets
- **Authentication**: Optional - can be configured for unauthenticated or authenticated access
  - If using authentication, configure username/password in the connector
  - If using unauthenticated, ensure the channel's MCAUSER is set appropriately
- **SSL/TLS**: Optional - configure cipher suite and keystores if required

**Note**: All these values are configurable via the `ibm-mq-source.env` file. The defaults match IBM MQ Developer edition out-of-the-box settings.

**IBM MQ Developer Edition Resources**:
- [Download IBM MQ](https://www.ibm.com/products/mq/developers)
- [Getting Started with IBM MQ](https://developer.ibm.com/tutorials/mq-connect-app-queue-manager-windows/)

### Connector Configuration

The connector uses a variable-based configuration system:
- `ibm-mq-source.json` - Template with variable placeholders
- `ibm-mq-source.env.example` - Example values for all variables
- `generate-config.sh` - Generates final config with values substituted

All MQ and JMS parameters are configurable via environment variables for security and flexibility.

**Note**: MQ credentials (username/password) are optional. If your IBM MQ server is configured to allow unauthenticated connections, you can leave these empty in the configuration. This is acceptable when relying on network-level security (Private Link, NSG, VPN), though using credentials provides defense-in-depth.

**SSL/TLS Support**: The connector supports custom keystore and truststore configuration for SSL/TLS connections to IBM MQ. Configure cipher suite, keystore location, and truststore settings in the environment file as needed.

### Generating SSL/TLS Keystores (Optional)

If your IBM MQ server requires SSL/TLS, you'll need to generate keystore and truststore files. Here's how:

#### 1. Create a Truststore (for IBM MQ server certificate)

```bash
# Import the IBM MQ server's certificate into a truststore
keytool -import -trustcacerts -alias ibm-mq-server \
  -file /path/to/mq-server-cert.pem \
  -keystore truststore.jks \
  -storepass your-truststore-password
```

#### 2. Create a Keystore (if mutual TLS is required)

```bash
# Generate a key pair
keytool -genkeypair -alias client-key \
  -keyalg RSA -keysize 2048 \
  -validity 365 \
  -keystore keystore.jks \
  -storepass your-keystore-password \
  -dname "CN=confluent-connector,OU=IT,O=YourOrg,L=City,ST=State,C=US"

# Export the certificate (to provide to IBM MQ admin)
keytool -export -alias client-key \
  -file client-cert.pem \
  -keystore keystore.jks \
  -storepass your-keystore-password
```

#### 3. Configure IBM MQ Server for SSL/TLS

On the IBM MQ server, import the client certificate and configure the channel:

```bash
# Create MQ key database (if not exists)
runmqakm -keydb -create -db /var/mqm/qmgrs/QM1/ssl/key.kdb \
  -pw your-mq-keydb-password -type cms -stash

# Import the client certificate into MQ's key database
runmqakm -cert -add -db /var/mqm/qmgrs/QM1/ssl/key.kdb \
  -stashed -label confluent-client \
  -file /path/to/client-cert.pem -format ascii

# Configure the server connection channel for SSL/TLS
runmqsc QM1 << EOF
ALTER CHANNEL(DEV.APP.SVRCONN) CHLTYPE(SVRCONN) SSLCIPH(TLS_RSA_WITH_AES_128_CBC_SHA256)
ALTER CHANNEL(DEV.APP.SVRCONN) CHLTYPE(SVRCONN) SSLCAUTH(OPTIONAL)
REFRESH SECURITY TYPE(SSL)
EOF
```

**Notes**:
- Adjust paths according to your MQ installation
- `SSLCAUTH(OPTIONAL)` allows connections with or without client certificates
- Use `SSLCAUTH(REQUIRED)` to enforce mutual TLS
- The cipher spec name may differ slightly between MQ and Java (e.g., `TLS_RSA_WITH_AES_128_CBC_SHA256`)
- Restart the queue manager after SSL configuration changes

#### 4. Configure in `ibm-mq-source.env`

```bash
MQ_SSL_CIPHER_SUITE=TLS_RSA_WITH_AES_128_CBC_SHA256
MQ_SSL_KEYSTORE_LOCATION=/path/to/keystore.jks
MQ_SSL_KEYSTORE_PASSWORD=your-keystore-password
MQ_SSL_TRUSTSTORE_LOCATION=/path/to/truststore.jks
MQ_SSL_TRUSTSTORE_PASSWORD=your-truststore-password
```

**Note**: The keystore/truststore files must be accessible to the Confluent Cloud connector. You may need to upload them as connector configuration files or use a supported secrets manager.

**Common IBM MQ Cipher Suites**:
- `TLS_RSA_WITH_AES_128_CBC_SHA256`
- `TLS_RSA_WITH_AES_256_CBC_SHA256`
- `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`

Consult your IBM MQ administrator for the correct cipher suite to use.

## Cost Estimate

- Application Gateway Standard_v2: ~$90-110/month (1 instance, configurable via capacity parameter)
- Private Link Service: Minimal cost
- Data transfer: Based on usage

## Support

For issues or questions, see the detailed troubleshooting section in [SETUP.md](SETUP.md).
