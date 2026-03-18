# Confluent Cloud Setup Guide

This guide explains how to set up Confluent Cloud credentials and configuration for automated egress endpoint provisioning.

## Prerequisites

1. Confluent Cloud account with admin access
2. Azure subscription with permissions to create resources
3. Terraform 1.3+ installed
4. Azure CLI installed and authenticated

## Step 1: Create Confluent Cloud API Keys

1. Log in to [Confluent Cloud Console](https://confluent.cloud)

2. Navigate to **Cloud Settings** → **API keys**

3. Click **Add key** → **Cloud API key**

4. Select **Granular access** and grant:
   - Environment: Read, Write
   - Network: Read, Write
   - Private Link: Read, Write

5. Save the API Key and Secret securely (you'll need these for `terraform.tfvars`)

## Step 2: Get Your Environment ID

1. In Confluent Cloud, navigate to **Environments**

2. Select the environment where you want to create the egress endpoint

3. The Environment ID is shown in the URL or in the environment details
   - Format: `env-xxxxx`

## Step 2b: Get Existing Network/Attachment IDs (Optional)

If you want to use existing Confluent Cloud resources:

### Get Network ID

1. In Confluent Cloud, navigate to your **Environment**

2. Go to **Network** → **Networking**

3. Click on the network you want to use

4. The Network ID is shown in the details
   - Format: `n-xxxxx`

**Or using Confluent CLI:**
```bash
confluent network list --environment env-xxxxx
```

### Get Private Link Attachment ID

1. In the same network view, look for **Private Link Attachments**

2. The Attachment ID is shown in the list
   - Format: `platt-xxxxx`

**Or using Confluent CLI:**
```bash
confluent network private-link attachment list --environment env-xxxxx
```

## Step 3: Get Your Azure Subscription ID

```bash
az account show --query id -o tsv
```

## Step 4: Configure terraform.tfvars

Copy the example file and fill in your values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set:

### Option A: Create New Confluent Cloud Network (Default)

```hcl
# Confluent Cloud Configuration
confluent_cloud_api_key    = "YOUR_CONFLUENT_API_KEY"
confluent_cloud_api_secret = "YOUR_CONFLUENT_API_SECRET"
confluent_environment_id   = "env-xxxxx"
confluent_cloud_region     = "westeurope"  # Must match your Azure location

# Azure Configuration
azure_subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# IBM MQ Backend - Your actual MQ servers
ibm_mq_backend_targets = ["10.0.2.10"]  # or ["mq.example.com"]
```

### Option B: Use Existing Confluent Cloud Network (CCN)

If you already have a Confluent Cloud network set up and want to add this egress endpoint to it:

```hcl
# Confluent Cloud Configuration
confluent_cloud_api_key    = "YOUR_CONFLUENT_API_KEY"
confluent_cloud_api_secret = "YOUR_CONFLUENT_API_SECRET"
confluent_environment_id   = "env-xxxxx"
confluent_cloud_region     = "westeurope"

# Use existing network
create_confluent_network      = false
existing_confluent_network_id = "n-xxxxx"

# Azure Configuration
azure_subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# IBM MQ Backend
ibm_mq_backend_targets = ["10.0.2.10"]
```

### Option C: Use Existing Private Link Attachment

If you have an existing Private Link Attachment you want to reuse:

```hcl
# Confluent Cloud Configuration
confluent_cloud_api_key    = "YOUR_CONFLUENT_API_KEY"
confluent_cloud_api_secret = "YOUR_CONFLUENT_API_SECRET"
confluent_environment_id   = "env-xxxxx"

# Use existing network and attachment
create_confluent_network            = false
existing_confluent_network_id       = "n-xxxxx"
create_private_link_attachment      = false
existing_private_link_attachment_id = "platt-xxxxx"

# Azure Configuration
azure_subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# IBM MQ Backend
ibm_mq_backend_targets = ["10.0.2.10"]
```

## Step 5: Deploy

```bash
# Initialize Terraform (first time only)
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

## What Gets Created

### Azure Resources
- Application Gateway with Private Link configuration
- Virtual Network and Subnets (or use existing)
- Network Security Groups
- Public IP (blocked from external access)

### Confluent Cloud Resources

**By default (new resources):**
- Egress Network (CCN) for private connectivity
- Private Link Attachment to Azure
- Private Link Connection to Application Gateway

**With existing resources:**
- Can reuse existing Confluent Cloud Network (CCN)
- Can reuse existing Private Link Attachment
- Still creates the connection to your Application Gateway

## When to Use Existing Confluent Resources

### Use Existing Network When:
- ✓ You have a shared Confluent Cloud network for all private connectivity
- ✓ You want multiple connectors to use the same network
- ✓ Your organization has a standard network setup
- ✓ You need to consolidate billing/resources

### Use Existing Private Link Attachment When:
- ✓ You've already set up the Azure subscription connection
- ✓ You want to add additional connections to the same attachment
- ✓ You're testing multiple Application Gateway configurations

### Create New Resources When:
- ✓ This is your first private connectivity setup
- ✓ You want isolated network per use case
- ✓ You're setting up in a new environment
- ✓ You want full Terraform management of all resources

## Post-Deployment

After `terraform apply` completes:

1. **Approve the Private Endpoint** (if not auto-approved):
   - Go to Azure Portal → Your Application Gateway
   - Navigate to **Private Link Center**
   - Find the pending connection from Confluent Cloud
   - Click **Approve**

2. **Configure TCP/TLS Proxy** (manual Azure Portal step):
   - See [TCP-PROXY-SETUP.md](TCP-PROXY-SETUP.md)
   - Change health probe to TCP
   - Change backend settings to HTTPS

3. **Deploy Your Connector**:
   - Use the Confluent Network ID from terraform output
   - Set connector to use the egress network
   - Point to the App Gateway private IP (shown in output)

## Troubleshooting

### "Environment not found" error
- Verify the `confluent_environment_id` is correct
- Ensure your API key has access to that environment

### "Insufficient permissions" error
- Check that your Confluent API key has the required scopes
- You need Network and Private Link permissions

### Private Link connection pending
- Check Azure Portal → App Gateway → Private Link Center
- Manually approve the connection if needed

### Terraform state conflicts
- If multiple people are running terraform, use remote state (S3, Azure Storage)
- See [Terraform Backend Configuration](https://www.terraform.io/docs/language/settings/backends/index.html)

### "Network not found" error
- Verify the network ID is correct (format: `n-xxxxx`)
- Ensure the network exists in the specified environment
- Check that your API key has access to that network
- Confirm the network is in the correct region

### "Private Link Attachment not found" error
- Verify the attachment ID is correct (format: `platt-xxxxx`)
- Ensure the attachment exists in the specified environment
- Check that the attachment is in the same region as your Azure resources
- Confirm your API key has the required permissions

### Using existing network but connection fails
- Ensure the existing network has `connection_types = ["PRIVATELINK"]`
- Verify the network is in the correct cloud (AZURE) and region
- Check that DNS resolution is set to PRIVATE
- Confirm the network is active and not in a failed state

## Security Best Practices

1. **Never commit terraform.tfvars** - It's already in `.gitignore`
2. **Use environment variables** for secrets in CI/CD:
   ```bash
   export TF_VAR_confluent_cloud_api_key="your-key"
   export TF_VAR_confluent_cloud_api_secret="your-secret"
   ```
3. **Rotate API keys regularly**
4. **Use separate Confluent API keys** for different environments (dev/staging/prod)
5. **Enable Azure Private Link approval** for production environments

## Region Mapping

Ensure Confluent Cloud region matches your Azure location:

| Azure Location | Confluent Region |
|---------------|------------------|
| westeurope    | westeurope       |
| eastus        | eastus           |
| westus2       | westus2          |

See [Confluent Cloud Regions](https://docs.confluent.io/cloud/current/clusters/regions.html) for full list.

## References

- [Confluent Cloud API Keys](https://docs.confluent.io/cloud/current/access-management/authenticate/api-keys/api-keys.html)
- [Azure Private Link with App Gateway](https://learn.microsoft.com/en-us/azure/application-gateway/private-link)
- [Confluent Terraform Provider](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs)
