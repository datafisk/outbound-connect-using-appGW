# Multi-Connector Setup Guide

This guide explains how to use the same Azure Application Gateway infrastructure to support multiple connectors (e.g., IBM MQ, Oracle, SQL Server, etc.).

## Architecture

```
Confluent Cloud
  ↓
  ├─ Connector 1 (IBM MQ) ──→ Private Link ──→ App Gateway Backend Pool 1 ──→ IBM MQ
  ├─ Connector 2 (Oracle) ──→ Private Link ──→ App Gateway Backend Pool 2 ──→ Oracle DB
  └─ Connector 3 (SQL)    ──→ Private Link ──→ App Gateway Backend Pool 3 ──→ SQL Server
                                    ↑
                            Same App Gateway Instance
```

## Deployment Strategy

### Step 1: Deploy Shared Infrastructure (One Time)

Deploy the base infrastructure **without** the connector:

```hcl
# terraform.tfvars
create_connector = false  # Skip connector deployment

# Azure infrastructure
create_resource_group = true
resource_prefix = "confluent-connectors"
location = "eastus"

# Confluent Cloud
confluent_environment_id = "env-xxxxx"
confluent_cloud_region = "eastus"

# Network settings
create_confluent_network = true
create_private_link_attachment = true
```

Deploy:
```bash
terraform init
terraform apply
```

This creates:
- Azure App Gateway with Private Link enabled
- VNet and subnets
- Confluent Cloud network
- Private Link attachment
- Egress access point

### Step 2: Add Backend Pools for Each Connector

For each connector, add a backend pool to the App Gateway:

**Option A: Via Terraform (update main.tf)**

```hcl
# Add to main.tf after the existing backend_address_pool block

# Backend pool for Oracle
backend_address_pool {
  name         = "oracle-backend-pool"
  ip_addresses = ["10.0.3.10"]  # Your Oracle server IP
}

# Backend pool for SQL Server
backend_address_pool {
  name         = "sql-backend-pool"
  ip_addresses = ["10.0.4.10"]  # Your SQL Server IP
}
```

**Option B: Via Azure Portal**

1. Go to App Gateway → Backend pools
2. Click "+ Add"
3. Configure backend pool for each connector

### Step 3: Configure TCP Routing for Each Backend

Since App Gateway is already configured for TCP proxy, you can add additional routing rules:

**Via PowerShell:**

```powershell
# Get App Gateway
$appgw = Get-AzApplicationGateway -ResourceGroupName "confluent-connectors-rg" -Name "confluent-connectors-appgw"

# Add frontend port for Oracle (port 1521)
Add-AzApplicationGatewayFrontendPort -ApplicationGateway $appgw -Name "oracle-port" -Port 1521

# Add TCP listener for Oracle
$frontendIP = $appgw.FrontendIpConfigurations | Where-Object { $_.Name -eq "appgw-frontend-private" }
$oraclePort = $appgw.FrontendPorts | Where-Object { $_.Name -eq "oracle-port" }

Add-AzApplicationGatewayListener `
  -ApplicationGateway $appgw `
  -Name "oracle-listener" `
  -Protocol Tcp `
  -FrontendIPConfiguration $frontendIP `
  -FrontendPort $oraclePort

# Add TCP backend settings for Oracle
Add-AzApplicationGatewayBackendSetting `
  -ApplicationGateway $appgw `
  -Name "oracle-settings" `
  -Port 1521 `
  -Protocol Tcp `
  -Timeout 20

# Add routing rule
$oracleListener = $appgw.Listeners | Where-Object { $_.Name -eq "oracle-listener" }
$oracleBackendPool = $appgw.BackendAddressPools | Where-Object { $_.Name -eq "oracle-backend-pool" }
$oracleBackendSettings = $appgw.BackendSettingsCollection | Where-Object { $_.Name -eq "oracle-settings" }

Add-AzApplicationGatewayRoutingRule `
  -ApplicationGateway $appgw `
  -Name "oracle-routing-rule" `
  -RuleType Basic `
  -Priority 101 `
  -Listener $oracleListener `
  -BackendAddressPool $oracleBackendPool `
  -BackendSettings $oracleBackendSettings

# Apply changes
Set-AzApplicationGateway -ApplicationGateway $appgw
```

### Step 4: Create DNS Records for Each Connector

```hcl
# Create separate DNS records via Confluent provider
resource "confluent_dns_record" "oracle_egress" {
  display_name = "oracle-egress-dns"

  domain = "oracle.yourdomain.com"

  environment {
    id = var.confluent_environment_id
  }

  gateway {
    id = confluent_access_point.appgw_egress.gateway[0].id
  }
}

resource "confluent_dns_record" "sql_egress" {
  display_name = "sql-egress-dns"

  domain = "sqlserver.yourdomain.com"

  environment {
    id = var.confluent_environment_id
  }

  gateway {
    id = confluent_access_point.appgw_egress.gateway[0].id
  }
}
```

### Step 5: Deploy Individual Connectors

Create separate connector configurations for each:

**IBM MQ Connector:**
```hcl
# ibm-mq-connector.tf
resource "confluent_connector" "ibm_mq" {
  environment {
    id = var.confluent_environment_id
  }

  kafka_cluster {
    id = var.kafka_cluster_id
  }

  config_nonsensitive = {
    "connector.class"          = "IbmMqSource"
    "kafka.topic"             = "ibm-mq-messages"
    "mq.hostname"             = "ibmmq2.peter.com"
    "mq.port"                 = "1414"
    "mq.queue.manager"        = "QM1"
    "mq.channel"              = "CONFLUENT.CHL"
    "jms.destination.name"    = "DEV.QUEUE.1"
    # ... other config
  }
}
```

**Oracle Connector:**
```hcl
# oracle-connector.tf
resource "confluent_connector" "oracle" {
  environment {
    id = var.confluent_environment_id
  }

  kafka_cluster {
    id = var.kafka_cluster_id
  }

  config_nonsensitive = {
    "connector.class"  = "OracleDatabaseSource"
    "connection.url"   = "jdbc:oracle:thin:@oracle.yourdomain.com:1521/ORCL"
    # ... other config
  }
}
```

## Example: Two-Connector Setup

**Directory structure:**
```
.
├── main.tf                    # Shared infrastructure
├── confluent.tf               # Shared Confluent resources
├── connectors/
│   ├── ibm-mq/
│   │   ├── connector.tf
│   │   └── variables.tf
│   └── oracle/
│       ├── connector.tf
│       └── variables.tf
└── terraform.tfvars
```

**Deploy in stages:**

```bash
# Stage 1: Deploy shared infrastructure
terraform apply -target=azurerm_application_gateway.main
terraform apply -target=confluent_network.main
terraform apply -target=confluent_access_point.appgw_egress

# Stage 2: Configure App Gateway for both backends
./scripts/add-backend-pool.ps1 -BackendName oracle -BackendIP 10.0.3.10 -Port 1521
./scripts/add-backend-pool.ps1 -BackendName sql -BackendIP 10.0.4.10 -Port 1433

# Stage 3: Deploy connectors individually
terraform apply -target=confluent_connector.ibm_mq
terraform apply -target=confluent_connector.oracle
```

## Cost Optimization

**Single App Gateway supports multiple connectors:**
- App Gateway Standard_v2: ~$90-110/month (shared across all connectors)
- Each connector: Confluent Cloud connector pricing only
- Private Link: Minimal cost (shared endpoint)

**vs. Multiple App Gateways:**
- 3 connectors × $100/month = $300/month
- With shared: $100/month total

## Best Practices

### 1. Use Separate Backend Pools
- One pool per connector type
- Allows independent health monitoring
- Easier troubleshooting

### 2. Use Different Ports
- MQ: 1414
- Oracle: 1521
- SQL: 1433
- Avoids port conflicts

### 3. Organize Terraform Modules
```
modules/
  ├── shared-infrastructure/
  │   ├── app-gateway.tf
  │   └── confluent-network.tf
  └── connectors/
      ├── ibm-mq/
      ├── oracle/
      └── sql/
```

### 4. Tag Resources Appropriately
```hcl
tags = {
  Environment = "production"
  ManagedBy   = "terraform"
  Purpose     = "confluent-connectors"
  Connector   = "ibm-mq"  # or "oracle", "sql", etc.
}
```

### 5. Use Separate DNS Records
- `ibmmq.yourdomain.com` → MQ connector
- `oracle.yourdomain.com` → Oracle connector
- `sqlserver.yourdomain.com` → SQL connector

## Troubleshooting Multi-Connector Setup

### Check Backend Health
```bash
az network application-gateway show-backend-health \
  --name confluent-connectors-appgw \
  --resource-group confluent-connectors-rg
```

### Verify Routing Rules
```powershell
$appgw = Get-AzApplicationGateway -ResourceGroupName "rg" -Name "appgw"
$appgw.RoutingRules | Format-Table Name, Priority, Listener, BackendPool
```

### Test Individual Backends
```bash
# From App Gateway subnet, test each backend
nc -zv 10.0.2.10 1414  # IBM MQ
nc -zv 10.0.3.10 1521  # Oracle
nc -zv 10.0.4.10 1433  # SQL Server
```

## Migration Path

**From single connector to multi-connector:**

1. Deploy first connector with `create_connector = true`
2. Verify it works
3. Set `create_connector = false` in main config
4. Add backend pools for additional connectors
5. Deploy additional connectors separately

**No downtime required** - existing connector continues working while you add new ones.
