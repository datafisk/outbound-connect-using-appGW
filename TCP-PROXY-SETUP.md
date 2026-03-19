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

## Option 1: Automated Configuration (PowerShell) ⭐ RECOMMENDED

Use the provided PowerShell script to automatically configure TCP proxy:

```powershell
.\scripts\configure-tcp-proxy.ps1 -ResourceGroup <name> -AppGatewayName <name>
```

**Example:**
```powershell
.\scripts\configure-tcp-proxy.ps1 -ResourceGroup vpc-peered-cce-se -AppGatewayName confluent-pl-appgw
```

**What it does:**
- ✓ Creates TCP listener on port 1414
- ✓ Configures TCP backend settings
- ✓ Updates health probe to use TCP protocol
- ✓ Creates TCP routing rule
- ✓ Removes old HTTP components

**Prerequisites:**
- PowerShell with Az module installed: `Install-Module -Name Az -AllowClobber -Scope CurrentUser`
- Azure authentication: `Connect-AzAccount`
- Contributor access to the resource group

**Estimated time:** 15-20 minutes (includes 3 Application Gateway updates)

---

## Option 2: Azure Portal Configuration (Manual)

**Estimated time:** 20-30 minutes

### Overview

The Azure Portal doesn't have a single button to convert HTTP to TCP. You'll need to:
1. Create new TCP components (listener, backend settings)
2. Create a new TCP routing rule
3. Delete the old HTTP components

### Detailed Steps

#### Step 1: Create TCP Listener

1. Open [Azure Portal](https://portal.azure.com)
2. Navigate to: **Resource Groups** → `vpc-peered-cce-se` → `confluent-pl-appgw`
3. Wait for the Application Gateway status to show **Succeeded** (top of page)
4. In the left menu, select **Listeners**
5. Click **+ Add listener**
6. Configure the TCP listener:
   - **Listener name**: `ibm-mq-listener`
   - **Frontend IP**: `appgw-frontend-private` (Private IP)
   - **Protocol**: `TCP`
   - **Port**: `1414`
   - **Listener type**: `Basic`
7. Click **Add**
8. Wait for the update to complete (Status: Updating → Succeeded, ~5 minutes)

#### Step 2: Update Health Probe to TCP

1. In the left menu, select **Health probes**
2. Click on `ibm-mq-health-probe`
3. Update the following:
   - **Protocol**: Change from `Http` to `Tcp`
   - **Port**: `1414`
   - **Interval**: `30` seconds
   - **Timeout**: `30` seconds
   - **Unhealthy threshold**: `3`
   - Remove any **Host** or **Path** settings (not needed for TCP)
4. Click **Save**
5. Wait for the update to complete (Status: Updating → Succeeded, ~5 minutes)

#### Step 3: Create TCP Backend Settings

1. In the left menu, select **Backend settings**
2. Click **+ Add**
3. Configure the TCP backend settings:
   - **Backend settings name**: `ibm-mq`
   - **Backend protocol**: `TCP`
   - **Backend port**: `1414`
   - **Timeout (seconds)**: `20`
   - **Custom probe**: Select `ibm-mq-health-probe`
4. Click **Add**
5. Wait for the update to complete (Status: Updating → Succeeded, ~5 minutes)

#### Step 4: Create TCP Routing Rule

1. In the left menu, select **Rules**
2. Click **+ Routing rule**
3. Configure the routing rule:
   - **Rule name**: `ibm-mq-routing-rule`
   - **Priority**: `100`
   - **Listener**: Select `ibm-mq-listener` (the TCP listener you created)
4. Click **Backend targets** tab
5. Configure backend targets:
   - **Target type**: `Backend pool`
   - **Backend target**: Select `ibm-mq-backend-pool`
   - **Backend settings**: Select `ibm-mq` (the TCP backend settings you created)
6. Click **Add**
7. Wait for the update to complete (Status: Updating → Succeeded, ~5 minutes)

#### Step 5: Delete Old HTTP Routing Rule

1. In the left menu, select **Rules**
2. Find the rule `ibm-mq-private-routing-rule`
3. Click the **...** menu on the right
4. Click **Delete**
5. Confirm the deletion
6. Wait for the update to complete (Status: Updating → Succeeded, ~5 minutes)

#### Step 6: Delete Old HTTP Listener

1. In the left menu, select **Listeners**
2. Find the listener `ibm-mq-private-listener`
3. Click the **...** menu on the right
4. Click **Delete**
5. Confirm the deletion
6. Wait for the update to complete (Status: Updating → Succeeded, ~5 minutes)

#### Step 7: Delete Old HTTP Backend Settings

1. In the left menu, select **Backend settings**
2. Find the settings `ibm-mq-backend-settings`
3. Click the **...** menu on the right
4. Click **Delete**
5. Confirm the deletion
6. Wait for the update to complete (Status: Updating → Succeeded, ~5 minutes)

#### Step 8: Verify TCP Configuration

1. In the left menu, select **Listeners**
   - Verify `ibm-mq-listener` shows Protocol: `TCP`
2. Select **Backend settings**
   - Verify `ibm-mq` shows Protocol: `TCP`
3. Select **Health probes**
   - Verify `ibm-mq-health-probe` shows Protocol: `Tcp`
4. Select **Rules**
   - Verify `ibm-mq-routing-rule` exists and is using the TCP components
5. Select **Backend health**
   - Verify backend targets show TCP health checks (may show unhealthy until IBM MQ is configured)

**✅ TCP Proxy configuration is complete!**

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
