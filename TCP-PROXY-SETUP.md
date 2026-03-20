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

## Configuration Required

The Terraform azurerm provider (v4.64.0) doesn't yet fully support TCP/TLS proxy configuration via code.
**Choose one of the following options to complete the TCP/TLS proxy setup:**

---

## Option 1: Automated Configuration (PowerShell)

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

### 1. Configure Firewalls to allow IBM MQ (Åsome examples)

**⚠️ CRITICAL STEP**: The IBM MQ server must allow connections from the Application Gateway subnet, this also includes firewalls in the path.

**Application Gateway Subnet**: Check your `appgw_subnet_prefix` in `terraform.tfvars`
- Default: `172.200.9.0/24`
- Example custom: `10.0.1.0/24`

#### Linux/Unix Firewall (iptables) if enabled

```bash
# Allow TCP 1414 from Application Gateway subnet
sudo iptables -A INPUT -p tcp --dport 1414 -s 172.200.9.0/24 -j ACCEPT
sudo iptables -L -n -v | grep 1414

# Make persistent (Ubuntu/Debian)
sudo netfilter-persistent save

# Make persistent (RHEL/CentOS)
sudo service iptables save
```

#### Linux/Unix Firewall (firewalld)

```bash
# Create rich rule for Application Gateway subnet
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="172.200.9.0/24" port protocol="tcp" port="1414" accept'
sudo firewall-cmd --reload
sudo firewall-cmd --list-all
```

#### Windows Firewall

```powershell
# Allow TCP 1414 from Application Gateway subnet
New-NetFirewallRule -DisplayName "IBM MQ - App Gateway" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 1414 `
  -RemoteAddress 172.200.9.0/24 `
  -Action Allow

# Verify the rule
Get-NetFirewallRule -DisplayName "IBM MQ - App Gateway" | Get-NetFirewallAddressFilter
```

#### IBM MQ Channel Authentication (CHLAUTH)

IBM MQ requires channel authentication rules to allow connections from the Application Gateway subnet.

**For the example connector configuration (channel: CONFLUENT.CHL):**

```bash
# Allow connections from App Gateway subnet and map to 'confluent' user
runmqsc QM1 << EOF
SET CHLAUTH('CONFLUENT.CHL') TYPE(ADDRESSMAP) ADDRESS('172.200.*') USERSRC(MAP) MCAUSER('confluent') ACTION(ADD)
EOF
```

**Note**: CHLAUTH rules take effect immediately, no refresh needed.

**For the default IBM MQ Developer channel (DEV.APP.SVRCONN):**

```bash
# Allow connections from App Gateway subnet
runmqsc QM1 << EOF
SET CHLAUTH('DEV.APP.SVRCONN') TYPE(ADDRESSMAP) ADDRESS('172.200.*') USERSRC(CHANNEL) CHCKCLNT(OPTIONAL)
EOF
```

**Explanation:**
- `TYPE(ADDRESSMAP)` - Map specific IP addresses to user identities
- `ADDRESS('172.200.*')` - Allow from entire 172.200.0.0/16 range (adjust to match your subnet)
- `USERSRC(MAP)` - Use mapped user from MCAUSER
- `MCAUSER('confluent')` - Run connections as this MQ user (must exist)
- `USERSRC(CHANNEL)` - Use the user ID from the channel definition (for DEV channel)
- `CHCKCLNT(OPTIONAL)` - Client certificate is optional

**Verify channel authentication:**

```bash
# Display all channel authentication records
echo "DISPLAY CHLAUTH('CONFLUENT.CHL')" | runmqsc QM1

# Or display all
echo "DISPLAY CHLAUTH(*)" | runmqsc QM1
```

**Create the 'confluent' user if needed:**

```bash
# Linux/Unix
sudo useradd -r -c "Confluent MQ User" -d /var/mqm confluent
sudo usermod -aG mqm confluent

# Windows
net user confluent ConfluentP@ss123 /add
# Then add to mqm group via Computer Management
```

#### IBM MQ Connection Authentication (CONNAUTH)

**Confluent Cloud Connector Requirement:**
The Confluent IBM MQ connector **mandates** a username to be set in the configuration, even if your MQ server doesn't require authentication. This can cause issues if MQ authentication checking is set to `OPTIONAL`.

**Configuration for Network-Level Security:**

If you're relying on network-level security (Private Link, NSG, CHLAUTH) and don't need MQ password validation, set connection authentication checking to `NONE`:

```bash
# Disable connection authentication checking
runmqsc QM1 << EOF
ALTER AUTHINFO(SYSTEM.DEFAULT.AUTHINFO.IDPWOS) AUTHTYPE(IDPWOS) CHCKCLNT(NONE)
REFRESH SECURITY TYPE(CONNAUTH)
EOF
```

**For IBM MQ Developer Edition:**

```bash
# Developer edition typically uses DEV.AUTHINFO
runmqsc QM1 << EOF
ALTER AUTHINFO(DEV.AUTHINFO) AUTHTYPE(IDPWOS) CHCKCLNT(NONE)
REFRESH SECURITY TYPE(CONNAUTH)
EOF
```

**Verify the configuration:**

```bash
# Display current connection authentication settings
echo "DISPLAY AUTHINFO(*)" | runmqsc QM1

# Check queue manager's CONNAUTH setting
echo "DISPLAY QMGR CONNAUTH" | runmqsc QM1
```

**Options Explained:**
- `CHCKCLNT(NONE)` - Don't validate client credentials (network security only)
- `CHCKCLNT(OPTIONAL)` - Validate if credentials provided ⚠️ **Don't use with Confluent connector**
- `CHCKCLNT(REQUIRED)` - Always validate credentials (need valid OS users)
- `CHCKCLNT(REQDADM)` - Validate for privileged users only

**Why CHCKCLNT(NONE) works for this setup:**
- Confluent connector always sends a username (cannot be disabled)
- With `CHCKCLNT(OPTIONAL)`, MQ will attempt to validate the username/password
- If validation fails, connection is rejected even though security is handled by Private Link
- `CHCKCLNT(NONE)` accepts any username without validation
- Security is enforced by:
  - Azure Private Link (network isolation)
  - Application Gateway subnet restrictions
  - IBM MQ CHLAUTH rules (IP-based access control)
  - Azure NSG rules

#### Azure Network Security Group (NSG) if MQ server runs in Azure, adjust accordingly for onprem access via corporate firewalls

Verify the backend subnet (where IBM MQ runs) allows traffic from App Gateway:

```bash
# Check NSG rules for IBM MQ backend subnet
az network nsg rule list \
  --resource-group <mq-rg> \
  --nsg-name <mq-nsg> \
  --query "[?destinationPortRange=='1414']" \
  -o table

# If needed, add rule to allow from App Gateway subnet
az network nsg rule create \
  --resource-group <mq-rg> \
  --nsg-name <mq-nsg> \
  --name AllowAppGatewayToMQ \
  --priority 100 \
  --source-address-prefixes 172.200.9.0/24 \
  --destination-port-ranges 1414 \
  --protocol Tcp \
  --access Allow \
  --direction Inbound
```

### 2. Add IBM MQ Backend Targets

Edit `terraform.tfvars`:
```hcl
ibm_mq_backend_targets = ["10.0.2.10"]  # Your IBM MQ server IP or FQDN
```

Run:
```bash
terraform apply
```

### 3. Approve Private Endpoint Connection

The private endpoint connection should already be approved if you followed the Quick Start guide.

Check status:
```bash
az network private-endpoint-connection list \
  --name confluent-pl-appgw \
  --resource-group vpc-peered-cce-se \
  --type Microsoft.Network/applicationGateways \
  -o table
```

If pending, approve it:
```bash
az network private-endpoint-connection approve \
  --name <connection-name> \
  --resource-group vpc-peered-cce-se \
  --resource-name confluent-pl-appgw \
  --type Microsoft.Network/applicationGateways \
  --description "Approved for Confluent Cloud egress"
```

Or via Azure Portal:
- Go to Application Gateway → Private Link Center
- Approve the pending connection from Confluent Cloud

### 4. Verify End-to-End Connectivity

Test the connection from Application Gateway to IBM MQ:

```bash
# From a VM in the same VNet as App Gateway, test MQ connectivity
nc -zv 10.33.0.4 1414

# Or use telnet
telnet 10.33.0.4 1414
```

Check Application Gateway backend health:
```bash
az network application-gateway show-backend-health \
  --name confluent-pl-appgw \
  --resource-group vpc-peered-cce-se \
  --query "backendAddressPools[0].backendHttpSettingsCollection[0].servers[0].health" \
  -o tsv
```

Expected output: `Healthy` (once firewall rules are configured)

### 5. Configure IBM MQ Connector

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

**Most Common Cause**: IBM MQ firewall not allowing connections from Application Gateway subnet.

1. **Verify IBM MQ firewall allows App Gateway subnet** (see Step 1 above)
   ```bash
   # On IBM MQ server, check if port 1414 is listening
   netstat -an | grep 1414
   # Or
   ss -tulpn | grep 1414
   ```

2. **Check Application Gateway can reach IBM MQ**
   ```bash
   # From a VM in the App Gateway subnet (172.200.9.0/24)
   nc -zv <mq-ip> 1414
   telnet <mq-ip> 1414
   ```

3. **Verify TCP health probe is configured correctly**
   - Protocol: `Tcp`
   - Port: `1414`
   - Verify via: Azure Portal → App Gateway → Health probes

4. **Check Azure NSG rules**
   ```bash
   # Verify NSG allows traffic from App Gateway subnet to MQ backend
   az network nsg rule list --resource-group <rg> --nsg-name <nsg> -o table
   ```

5. **Check IBM MQ listener status**
   ```bash
   # On IBM MQ server
   echo "DISPLAY LISTENER(*)" | runmqsc QM1
   ```

6. **Review IBM MQ channel authentication** ⚠️ Common Issue
   ```bash
   # Check channel authentication records for your channel
   echo "DISPLAY CHLAUTH('CONFLUENT.CHL')" | runmqsc QM1

   # Check all channel auth records
   echo "DISPLAY CHLAUTH(*)" | runmqsc QM1
   ```

   **Common error**: Channel blocked by CHLAUTH rules
   - **Symptom**: Connection refused or MQRC_NOT_AUTHORIZED (2035)
   - **Solution**: Add ADDRESSMAP rule (see Step 1 above)

   **If you see blocking rules:**
   ```bash
   # Example output showing a blocking rule:
   # CHLAUTH('CONFLUENT.CHL') TYPE(ADDRESSMAP) ADDRESS('*') ACTION(BLOCK)

   # You must add an ALLOW rule for your App Gateway subnet:
   SET CHLAUTH('CONFLUENT.CHL') TYPE(ADDRESSMAP) ADDRESS('172.200.*') USERSRC(MAP) MCAUSER('confluent') ACTION(ADD)
   ```

### Connection Times Out

1. **Verify IBM MQ firewall** (see above)
2. **Verify Private Endpoint connection is approved**
   ```bash
   az network private-endpoint-connection show \
     --name <connection-name> \
     --resource-group vpc-peered-cce-se \
     --resource-name confluent-pl-appgw \
     --type Microsoft.Network/applicationGateways \
     --query "privateLinkServiceConnectionState.status" -o tsv
   ```
   Expected: `Approved`

3. **Check Private Link state**
   ```bash
   az network application-gateway show \
     --name confluent-pl-appgw \
     --resource-group vpc-peered-cce-se \
     --query "provisioningState" -o tsv
   ```
   Expected: `Succeeded`

4. **Verify backend targets are reachable from App Gateway subnet**
   ```powershell
   # From a Windows VM in the VNet
   Test-NetConnection -ComputerName <mq-ip> -Port 1414
   ```

### Connector Shows "Could not connect to IbmMQ hosts"

1. **Verify TCP proxy is configured** (not HTTP)
   - Check listener protocol is `Tcp` (not `Http`)
   - Check backend settings protocol is `Tcp` (not `Http`)

2. **Verify firewall rules** (see Step 1 in Next Steps)

3. **Check DNS resolution** (if using DNS record)
   ```bash
   # From Confluent Cloud connector logs
   nslookup ibmmq2.peter.com
   ```

4. **Verify MQ channel is running**
   ```bash
   echo "DISPLAY CHANNEL(DEV.APP.SVRCONN)" | runmqsc QM1
   ```

5. **Check MQ connection authentication**
   ```bash
   # Review connection auth settings
   echo "DISPLAY AUTHINFO(*)" | runmqsc QM1
   ```

### Common IBM MQ Error Codes

**MQRC_NOT_AUTHORIZED (2035)**
- **Cause 1**: Channel authentication blocking the connection
  - **Solution**: Add CHLAUTH rule for App Gateway subnet (see Step 1)
  - **Verify**:
    ```bash
    echo "DISPLAY CHLAUTH('CONFLUENT.CHL')" | runmqsc QM1
    ```
- **Cause 2**: Connection authentication validation failure
  - **Symptom**: Error even with valid CHLAUTH rules
  - **Root Cause**: Confluent connector sends username, MQ set to CHCKCLNT(OPTIONAL) tries to validate
  - **Solution**: Set connection authentication to CHCKCLNT(NONE)
    ```bash
    runmqsc QM1 << EOF
    ALTER AUTHINFO(DEV.AUTHINFO) AUTHTYPE(IDPWOS) CHCKCLNT(NONE)
    REFRESH SECURITY TYPE(CONNAUTH)
    EOF
    ```
  - **Verify**:
    ```bash
    echo "DISPLAY AUTHINFO(DEV.AUTHINFO)" | runmqsc QM1
    echo "DISPLAY QMGR CONNAUTH" | runmqsc QM1
    ```

**MQRC_CHANNEL_NOT_AVAILABLE (2537)**
- **Cause**: Channel not running or not defined
- **Solution**: Start the channel
  ```bash
  echo "START CHANNEL('CONFLUENT.CHL') CHLTYPE(SVRCONN)" | runmqsc QM1
  ```

**MQRC_CONNECTION_BROKEN (2009)**
- **Cause**: Firewall blocking connection or SSL/TLS mismatch
- **Solution**:
  - Verify OS firewall allows App Gateway subnet
  - Check SSL cipher specs match
  - Review MQ error logs: `/var/mqm/qmgrs/QM1/errors/AMQERR*.LOG`

**MQRC_HOST_NOT_AVAILABLE (2538)**
- **Cause**: Network connectivity issue
- **Solution**: Verify App Gateway can reach MQ server (see connectivity tests above)

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
