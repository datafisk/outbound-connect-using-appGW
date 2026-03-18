# Setup Guide: Azure Application Gateway with Private Link for Confluent Cloud

This guide walks you through deploying an Azure Application Gateway configured for Private Link connectivity from Confluent Cloud to access on-premises or private resources like IBM MQ.

## Architecture Overview

```
Confluent Cloud (Managed Connectors)
         ↓ (Private Link)
    Azure Private Link Service
         ↓
    Application Gateway (Standard v2)
         ↓
    Backend Resources (IBM MQ, databases, APIs, etc.)
```

## Prerequisites

1. **Azure CLI** - Authenticated with appropriate permissions
   ```bash
   az login
   az account show
   ```

2. **Terraform** - Version 1.3 or higher
   ```bash
   terraform version
   ```

3. **Confluent Cloud Account** - With access to create Private Link connections

## Deployment Steps

### 1. Initialize Terraform

```bash
# Initialize Terraform and download providers
terraform init
```

### 2. Review and Customize Variables

Copy the example tfvars file and customize:
```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` to match your requirements:
- Azure region
- Resource naming
- Network addressing
- IBM MQ backend IP (if available)
- Tags

### 3. Plan the Deployment

```bash
# Review what will be created
terraform plan
```

This will create:
- Resource Group
- Virtual Network with two subnets (App Gateway, Backend)
- Network Security Group with required rules
- Public IP for Application Gateway
- Application Gateway (Standard_v2) with Private Link configuration
- Private Link Service

### 4. Deploy Infrastructure

```bash
# Apply the Terraform configuration
terraform apply
```

Review the plan and type `yes` to confirm.

Deployment takes approximately 10-15 minutes for the Application Gateway to be fully provisioned.

### 5. Retrieve Private Link Information

After deployment, get the Private Link Service details:

```bash
# View all outputs
terraform output

# Get the Private Link Service Alias (needed for Confluent Cloud)
terraform output private_link_service_alias

# Get connection instructions
terraform output confluent_connection_instructions
```

### 6. Configure Confluent Cloud Private Link

1. Log in to Confluent Cloud Console
2. Navigate to your Environment → Network
3. Click "Add network" → "Private Link"
4. Select Azure and your region (must match: `westeurope`)
5. Enter the Private Link Service Alias from the terraform output
6. Create the connection

### 7. Approve Private Link Connection

After Confluent Cloud creates the Private Link endpoint, approve it:

```bash
# List pending connections
az network private-link-service list \
  --resource-group $(terraform output -raw resource_group_name)

# Approve the connection (you'll see it pending)
# This can also be done in Azure Portal under the Private Link Service
```

Alternatively, Confluent Cloud will provide the private endpoint connection name which you can approve directly.

### 8. Configure Backend Resources

If you haven't already, deploy your IBM MQ server (or other backend) to the backend subnet:

```bash
# Get the backend subnet ID
terraform output backend_subnet_id
```

Place your IBM MQ server or other resources in this subnet, or configure routing to reach them.

### 9. Configure Connector Variables

Create your connector configuration from the example:

```bash
# Copy the example environment file
cp connectors/ibm-mq-source.env.example connectors/ibm-mq-source.env

# Edit the configuration with your values
# Update MQ_HOSTNAME with the Application Gateway private IP
MQ_HOSTNAME=$(terraform output -raw application_gateway_private_ip)
```

Edit `connectors/ibm-mq-source.env` with your actual values:
- **MQ_HOSTNAME**: Application Gateway private IP (from terraform output above)
- **MQ_PORT**: IBM MQ port (default: 1414)
- **MQ_QUEUE_MANAGER**: Your queue manager name
- **MQ_CHANNEL**: MQ channel name (e.g., DEV.APP.SVRCONN)
- **MQ_USERNAME** / **MQ_PASSWORD**: IBM MQ credentials
- **JMS_DESTINATION_NAME**: Queue or topic name
- **CONFLUENT_API_KEY** / **CONFLUENT_API_SECRET**: Kafka API credentials
- **CONFLUENT_BOOTSTRAP_SERVERS**: Your Confluent Cloud bootstrap servers

### 10. Generate and Deploy Connector Configuration

Generate the final connector configuration with variables substituted:

```bash
# Generate the configuration file
cd connectors
./generate-config.sh

# This creates ibm-mq-source.generated.json with all variables replaced
```

Deploy using the Confluent Cloud UI or CLI:

```bash
# Option 1: Using Confluent CLI (if installed)
confluent connect create --config connectors/ibm-mq-source.generated.json

# Option 2: Via Confluent Cloud Console
# Navigate to Connectors → IBM MQ Source
# Upload or paste the content from ibm-mq-source.generated.json
```

**Note**: The `.env` and `.generated.json` files contain credentials and are automatically ignored by git.

## Validation

### Test Application Gateway

```bash
# Get the public IP
PUBLIC_IP=$(terraform output -raw application_gateway_public_ip)

# Test connectivity
curl -v http://$PUBLIC_IP
```

### Monitor Connector

1. Check connector status in Confluent Cloud Console
2. Monitor messages flowing to the configured topic
3. Check Application Gateway metrics in Azure Portal

### View Application Gateway Logs

```bash
# Enable diagnostics if needed
az monitor diagnostic-settings create \
  --resource $(terraform output -raw application_gateway_id) \
  --name appgw-diagnostics \
  --logs '[{"category":"ApplicationGatewayAccessLog","enabled":true}]' \
  --workspace <your-log-analytics-workspace-id>
```

## Troubleshooting

### Private Link Connection Pending

If the connection stays pending:
1. Verify you're using the correct region
2. Check NSG rules allow traffic
3. Manually approve in Azure Portal

### Connector Cannot Connect

1. Verify Application Gateway is running: `az network application-gateway show`
2. Check backend health: Azure Portal → Application Gateway → Backend Health
3. Verify Private Link Service is active
4. Ensure IBM MQ is reachable from the Application Gateway subnet
5. Check NSG rules on backend subnet

### Backend Health Shows Unhealthy

1. Verify backend IP is correct
2. Check IBM MQ is listening on the configured port
3. Adjust health probe settings in `main.tf` if needed
4. Verify firewall rules on IBM MQ server allow traffic from App Gateway subnet

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete all resources including the Application Gateway, Virtual Network, and Private Link Service. Ensure you've backed up any necessary configurations.

## Cost Optimization

- Application Gateway Standard_v2 runs approximately $0.25-0.30/hour (~$180-220/month)
- Consider reducing `capacity` in `terraform.tfvars` for dev/test (minimum is 1)
- Use autoscaling in production (modify the SKU configuration)
- Private Link Service has minimal additional cost
- Data transfer charges apply based on usage

## Next Steps

1. **Add SSL/TLS**: Configure certificates for HTTPS listeners
2. **Add WAF**: Upgrade to WAF_v2 SKU for Web Application Firewall protection
3. **Implement Autoscaling**: Configure min/max capacity based on load
4. **Add Monitoring**: Set up Azure Monitor alerts and dashboards
5. **Multiple Backends**: Add more backend pools for different services
6. **Custom Health Probes**: Configure health checks specific to your services

## Additional Resources

- [Azure Application Gateway Documentation](https://docs.microsoft.com/en-us/azure/application-gateway/)
- [Azure Private Link Service](https://docs.microsoft.com/en-us/azure/private-link/private-link-service-overview)
- [Confluent Cloud Private Link](https://docs.confluent.io/cloud/current/networking/private-links/azure-privatelink.html)
- [IBM MQ Source Connector](https://docs.confluent.io/kafka-connectors/ibm-mq-source/current/overview.html)
