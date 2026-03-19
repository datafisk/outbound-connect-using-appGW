# Azure Application Gateway TCP/TLS Proxy Configuration

## Current Status

✅ **Infrastructure Deployed Successfully:**
- Azure Application Gateway Standard v2
- Virtual Network with subnets
- Network Security Groups
- Private Link Configuration enabled
- Listener on port 1414
- Backend pool configured
- Health probe configured

## ⚠️ Configuration Required

The Terraform azurerm provider (v4.64.0) doesn't yet fully support TCP/TLS proxy configuration via code.
**Choose one of the following options to complete the TCP/TLS proxy setup:**

---

## Option 1: Automated Configuration (Azure CLI) ⭐ RECOMMENDED

Use the provided script to automatically configure TCP proxy using Azure CLI:

```bash
./scripts/configure-tcp-proxy.sh <resource-group> <app-gateway-name>
```

**Example:**
```bash
./scripts/configure-tcp-proxy.sh vpc-peered-cce-se confluent-pl-appgw
```

**What it does:**
- ✓ Creates TCP listener on port 1414
- ✓ Configures TCP backend settings
- ✓ Updates health probe to use TCP protocol
- ✓ Updates routing rule to use TCP components

**Prerequisites:**
- Azure CLI installed and authenticated
- Contributor access to the resource group

**Terraform Integration:**

You can also enable automatic configuration via Terraform:

```hcl
# terraform.tfvars
auto_configure_tcp_proxy = true
```

Then run:
```bash
terraform apply
```

The script will run automatically after the Application Gateway is created.

---

## Option 2: Azure Portal Configuration (Manual)

### Step 1: Configure TCP Health Probe

1. Open [Azure Portal](https://portal.azure.com)
2. Navigate to: **Resource Groups** → `confluent-pl-rg` → `confluent-pl-appgw`
3. In the left menu, select **Health probes**
4. Click on `ibm-mq-health-probe`
5. Update the following:
   - **Protocol**: Change from `Http` to `Tcp`
   - **Port**: `1414`
   - **Interval**: `30` seconds
   - **Timeout**: `30` seconds
   - **Unhealthy threshold**: `3`
6. Click **Save**

### Step 2: Update Backend Settings for TLS

1. In the same Application Gateway, select **Backend settings**
2. Click on `ibm-mq-backend-settings`
3. Update the following:
   - **Backend protocol**: Change from `Http` to `Https`
   - **Backend port**: `1414`
   - **Custom probe**: Select `ibm-mq-health-probe`
   - **Override with new host name**: `No`
4. Click **Save**

### Step 3: Verify Configuration

1. Wait for the Application Gateway to finish updating (Status: Succeeded)
2. Go to **Backend health**
3. Once you add backend targets, you should see TCP health checks

---

##Option 2: Azure CLI Configuration

```bash
# 1. Get Application Gateway resource
RESOURCE_GROUP="confluent-pl-rg"
APPGW_NAME="confluent-pl-appgw"

# 2. Export current configuration
az network application-gateway show \
  --name "$APPGW_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  > appgw-config.json

# 3. Manually edit appgw-config.json:
#    - Find "probes" section
#    - Change "ibm-mq-health-probe" protocol to "Tcp"
#    - Find "backendHttpSettingsCollection" section
#    - Change "ibm-mq-backend-settings" protocol to "Https"

# 4. Apply the updated configuration
az network application-gateway update \
  --name "$APPGW_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --set properties=@appgw-config.json
```

---

## What This Enables

### TCP/TLS Proxy Mode
- **Frontend**: Accepts TCP connections on port 1414
- **Backend**: Forwards TCP traffic with TLS encryption to IBM MQ servers
- **Health Check**: TCP connection test to port 1414 on backend servers

### How It Works
```
Confluent Cloud Connector
    ↓ (Private Link - TCP/TLS)
Application Gateway Private Frontend (10.0.1.10:1414)
    ↓ (TCP/TLS Proxy)
IBM MQ Backend Server (configured in backend pool)
```

---

## Next Steps After Configuration

### 1. Add IBM MQ Backend Targets

Edit `terraform.tfvars`:
```hcl
ibm_mq_backend_targets = ["10.0.2.10"]  # Your IBM MQ server IP or FQDN
```

Run:
```bash
terraform apply
```

### 2. Create Private Link Connection in Confluent Cloud

Use the Application Gateway Resource ID:
```
/subscriptions/8018576d-fc49-402a-bb75-7437bff60635/resourceGroups/confluent-pl-rg/providers/Microsoft.Network/applicationGateways/confluent-pl-appgw
```

### 3. Approve Private Endpoint Connection

In Azure Portal:
- Go to Application Gateway → Private Link Center
- Approve the pending connection from Confluent Cloud

### 4. Configure IBM MQ Connector

```bash
# Update connector configuration
cd connectors
cp ibm-mq-source.env.example ibm-mq-source.env

# Edit ibm-mq-source.env with:
# - MQ_HOSTNAME: Private Endpoint DNS/IP from Confluent Cloud
# - MQ_PORT: 1414
# - MQ credentials and queue manager details

# Generate final configuration
./generate-config.sh

# Deploy to Confluent Cloud
```

---

## Troubleshooting

### Backend Health Shows Unhealthy

1. Verify TCP health probe is configured correctly
2. Check that IBM MQ is listening on port 1414
3. Verify NSG rules allow traffic from App Gateway subnet to backend
4. Check IBM MQ firewall allows connections from 10.0.1.0/24

### Connection Times Out

1. Verify Private Endpoint connection is approved
2. Check that Private Link is in "Succeeded" state
3. Verify backend targets are reachable from App Gateway subnet
4. Test connectivity: `Test-NetConnection -ComputerName <mq-ip> -Port 1414`

---

## Reference

- [Azure Application Gateway TCP/TLS Proxy Documentation](https://learn.microsoft.com/en-us/azure/application-gateway/how-to-tcp-tls-proxy)
- [Confluent Cloud Private Link for Azure](https://docs.confluent.io/cloud/current/networking/private-links/azure-privatelink.html)
- [IBM MQ Connection Configuration](https://www.ibm.com/docs/en/ibm-mq)

---

## Summary

Your Application Gateway is **deployed and ready**. You just need to:
1. ✅ Switch health probe to TCP protocol (via Azure Portal)
2. ✅ Switch backend settings to HTTPS protocol (via Azure Portal)
3. ✅ Add IBM MQ backend targets
4. ✅ Create and approve Private Link connection
5. ✅ Deploy connector to Confluent Cloud

The infrastructure supports TCP/TLS proxy - the configuration just needs to be completed via Azure Portal due to Terraform provider limitations.
