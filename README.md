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

### Multi-Connector Support
- ✅ Single App Gateway supports multiple connectors (IBM MQ, Oracle, SQL Server, etc.)
- ✅ Shared infrastructure reduces costs
- ✅ Independent backend pools and routing rules per connector
- ✅ See [MULTI-CONNECTOR.md](MULTI-CONNECTOR.md) for multi-connector setup guide

### Azure Infrastructure
- ✅ Azure Application Gateway Standard v2 with Private Link configuration
- ✅ **Native TCP/TLS proxy configuration via Terraform**
- ✅ Support for existing Azure Resource Groups, VNets, AppGW backends, load balancing rules and Subnets
- ✅ Production-ready security settings
- ✅ Private-only access (no public listener configured)

### Confluent Cloud Integration
- ✅ Automated Confluent Cloud egress endpoint provisioning
- ✅ Support for existing Confluent Cloud Networks and Attachments
- ✅ Private Link Service for Confluent Cloud integration
- ✅ Automated DNS record creation for access points
- ✅ Automated IBM MQ Source connector deployment via Terraform

### Flexibility
- ✅ Optional SSL/TLS support for backend connections
- ✅ Supports various IBM MQ authentication setups (no password and optional password auth)
- ✅ Extendable to support other connectors with the same Azure AppGW infra

## Security

**Public IP Configuration:**
Azure Application Gateway Standard v2 requires a public IP address for management operations, but this does not mean your gateway is exposed to the internet. In this configuration:

- The Application Gateway has **no listener configured on the public IP**
- Without a listener, the gateway **silently drops all incoming packets** to the public IP
- All traffic flows through the **private frontend IP** via Private Link (Confluent Cloud → Private Endpoint → App Gateway Private IP → Backend)
- For additional protection, you can apply **Azure DDoS Protection Standard** to the public IP address

This design ensures your backend resources remain completely isolated from public internet access while maintaining Azure's management capabilities.

## TCP/TLS Proxy Configuration

**✅ As of April 2026**, the Terraform azurerm provider now **fully supports** TCP/TLS proxy configuration for Application Gateway with native `listener`, `backend_settings`, and `routing_rule` blocks.

This infrastructure is now **100% managed by Terraform** with no manual configuration required. The Application Gateway will be deployed with full TCP proxy capabilities automatically.

## Quick Start

1. **Prerequisites**:
   - Azure CLI (logged in)
   - Terraform 1.3+

2. **Configure Confluent Cloud Credentials**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your Confluent Cloud API keys and Azure subscription
   ```
   See [CONFLUENT-SETUP.md](CONFLUENT-SETUP.md) for detailed credential setup.

3. **Deploy** (creates both Azure and Confluent Cloud resources with TCP proxy):
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Approve Private Endpoint Connection**:
   ```bash
   # Automated via Azure CLI
   az network private-endpoint-connection approve \
     --name <connection-name> --resource-group <rg-name> \
     --resource-name <appgw-name> --type Microsoft.Network/applicationGateways
   ```
   Or via Azure Portal → Application Gateway → Private Link Center → Approve

5. **(Optional) IBM MQ Connector**:
   - Set `create_connector = true` in `terraform.tfvars`
   - Configure connector variables (kafka_cluster_id, MQ settings, etc.)
   - The connector deploys automatically with step 6
   - Check status: `terraform output connector_status`

8. **(Optional) Test Message Generation**:
   - Use the message generator script to continuously put test messages onto the queue:
     ```bash
     # Standard authentication (run as mqm user)
     sudo -u mqm ./scripts/mq-message-generator.sh DEV.QUEUE.1 QM1 30

     # With mutual TLS
     export MQSSLKEYR=/path/to/ssl-certs/connector-keystore
     ./scripts/mq-message-generator.sh DEV.QUEUE.1 QM1 30 ssl
     ```
   - Validates connector is consuming messages and producing to Kafka
   - Generates JSON messages every 30 seconds (configurable)
   - Supports both standard and SSL/TLS authentication modes
   - Run as mqm user to avoid local authentication issues

## What's Included

### Terraform Infrastructure
- `main.tf` - Core Azure infrastructure (VNet, App Gateway with TCP proxy, Private Link)
- `confluent.tf` - Confluent Cloud egress endpoint automation
- `variables.tf` - Customizable variables (Azure + Confluent + Connector)
- `outputs.tf` - Connection details and setup instructions
- `terraform.tfvars.example` - Example configuration with all required variables

### Automation Scripts
- `scripts/setup-mutual-tls.sh` - Automated mutual TLS setup with self-signed CA
- `scripts/cleanup-mutual-tls.sh` - Clean up SSL certificates and reset configuration
- `scripts/mq-message-generator.sh` - Generate test messages for connector validation

### Documentation
- `TCP-PROXY-SETUP.md` - TCP/TLS proxy setup guide (PowerShell + Portal)
- `SSL-TLS-SETUP.md` - Mutual TLS setup guide with certificate generation
- `MULTI-CONNECTOR.md` - Multi-connector deployment guide (share infrastructure)
- `CONFLUENT-SETUP.md` - Confluent Cloud credential setup guide
- `EXISTING-RESOURCES.md` - Using existing Resource Groups/VNets/Subnets
- `SETUP.md` - Detailed step-by-step guide

**IBM MQ Connector**: Optionally deployed via Terraform by setting `create_connector = true`

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
- **Network Access**: ⚠️ **CRITICAL** - Must allow connections from Application Gateway subnet
  - **Step 1: Add Application Gateway subnet to OS firewall allow list**
    - Default subnet: `172.200.9.0/24` (or your custom `appgw_subnet_prefix`)
    - Example firewall rule: Allow TCP 1414 from 172.200.9.0/24
  - **Step 2: Configure IBM MQ Channel Authentication (CHLAUTH)**
    - Required: Add channel auth rule for Application Gateway subnet
    - Example for CONFLUENT.CHL channel:
      ```bash
      SET CHLAUTH('CONFLUENT.CHL') TYPE(ADDRESSMAP) ADDRESS('172.200.*') USERSRC(MAP) MCAUSER('confluent') ACTION(ADD)
      ```
    - See TCP-PROXY-SETUP.md for complete configuration
- **Authentication**: ⚠️ **Important Confluent Connector Requirement**
  - The Confluent connector **requires** a username to be set (even if blank password)
  - Setting MQ connection authentication to `CHCKCLNT(NONE)` it does not validate password for users
  - Command: `ALTER AUTHINFO(DEV.AUTHINFO) AUTHTYPE(IDPWOS) CHCKCLNT(NONE)`
  - This allows network-level security (Private Link + CHLAUTH) without credential validation
  - Alternative: Create valid users for the connector credentials (recommended production setup)
  - See TCP-PROXY-SETUP.md for complete authentication configuration
- **SSL/TLS**: Optional - configure cipher suite and keystores if required

**Note**: All these values are configurable via the `ibm-mq-source.env` file. The defaults match IBM MQ Developer edition out-of-the-box settings.

**IBM MQ Developer Edition Resources**:
- [Download IBM MQ](https://www.ibm.com/products/mq/developers)
- [Getting Started with IBM MQ](https://developer.ibm.com/tutorials/mq-connect-app-queue-manager-windows/)

### Connector Configuration

The IBM MQ Source connector can be deployed automatically via Terraform:

1. **Enable connector deployment** in `terraform.tfvars`:
   ```hcl
   create_connector = true
   connector_name   = "ibm-mq-source-connector"

   # Kafka Cluster
   kafka_cluster_id = "lkc-xxxxx"
   kafka_api_key    = "YOUR_KAFKA_API_KEY"
   kafka_api_secret = "YOUR_KAFKA_API_SECRET"
   kafka_topic      = "ibm-mq-messages"

   # IBM MQ Settings (uses defaults: QM1, DEV.APP.SVRCONN, DEV.QUEUE.1)
   mq_queue_manager     = "QM1"
   mq_channel           = "DEV.APP.SVRCONN"
   jms_destination_name = "DEV.QUEUE.1"

   # Optional: MQ Credentials
   mq_username = "mqadmin"
   mq_password = "your-password"
   ```

2. **Deploy with Terraform**:
   ```bash
   terraform apply
   ```

The connector automatically uses the DNS name (if created) or the private endpoint IP address for the MQ connection.

**Note**: MQ passwords are optional. If your IBM MQ server is configured to allow unauthenticated connections, you can leave the password empty. This might be acceptable when relying on network-level security (Private Link, NSG), though using credentials provides defense-in-depth and is a likely setup in any production environment.

### SSL/TLS Support (Optional)

For mutual TLS authentication between the connector and IBM MQ, use the automated setup script:

```bash
# On the IBM MQ server (use your dns_domain from terraform.tfvars)
./scripts/setup-mutual-tls.sh ibmmq2.peter.com
```

This creates:
- Self-signed Certificate Authority
- IBM MQ server certificate (signed by CA)
- Confluent connector client certificate (signed by CA)
- Java keystores (keystore.jks, truststore.jks)
- Configures IBM MQ for mutual TLS

Then configure the connector in `terraform.tfvars`:

```hcl
mq_ssl_cipher_suite = "SSL_RSA_WITH_AES_128_CBC_SHA256"
mq_ssl_keystore_location = "<path-to-keystore>"
mq_ssl_keystore_password = "connector-keystore-123"
mq_ssl_truststore_location = "<path-to-truststore>"
mq_ssl_truststore_password = "connector-truststore-123"
```

**For complete SSL/TLS setup instructions**, including certificate management, troubleshooting, and production best practices, see [SSL-TLS-SETUP.md](SSL-TLS-SETUP.md).

## Cost Estimate

- Application Gateway Standard_v2: ~$90-110/month (1 instance, configurable via capacity parameter)
- Private Link Service: Minimal cost
- Data transfer: Based on usage

## Support

For issues or questions, see the detailed troubleshooting section in [SETUP.md](SETUP.md).
