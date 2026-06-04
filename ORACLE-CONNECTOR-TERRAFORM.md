# Oracle JDBC Connector - Terraform Deployment Guide

Automate Oracle JDBC Source Connector deployment using Terraform alongside your Application Gateway infrastructure.

## Overview

This guide covers deploying the Confluent Cloud Oracle JDBC Source Connector via Terraform, which provides:

✅ **Infrastructure as Code** - Version control your connector configuration  
✅ **Automated Deployment** - Deploy AppGW and connector together  
✅ **Consistent Environments** - Replicate across dev/staging/prod  
✅ **Drift Detection** - Terraform tracks configuration changes  

---

## Prerequisites

### 1. Oracle RAC Setup

- Oracle RAC cluster accessible from Azure AppGW
- Oracle user created with SELECT privileges on target tables
- `REMOTE_LISTENER` configured with FQDN (see [ORACLE-RAC-QUICKSTART.md](ORACLE-RAC-QUICKSTART.md))

### 2. Azure Infrastructure

- Application Gateway with Oracle backend pool configured
- Network connectivity from AppGW to Oracle RAC nodes
- (Completed via `appgw-oracle-rac.tf`)

### 3. Confluent Cloud

- Environment and Kafka cluster created
- EAP provisioned and DNS wildcard configured
- Cloud API key pair for connector deployment
- Kafka API key pair for connector to use

---

## Quick Start

### 1. Create API Keys

```bash
# Cloud API Key (for Terraform to deploy connector)
confluent api-key create --resource cloud \
  --description "Terraform Oracle Connector Deployment"
# Save: CLOUD_API_KEY and CLOUD_API_SECRET

# Kafka API Key (for connector to use)
confluent api-key create --resource lkc-xxxxx \
  --description "Oracle JDBC Connector"
# Save: KAFKA_API_KEY and KAFKA_API_SECRET
```

### 2. Configure terraform.tfvars

```hcl
# Enable Oracle connector deployment
create_oracle_connector = true

# Confluent Cloud Credentials
confluent_cloud_api_key    = "CLOUD_API_KEY"
confluent_cloud_api_secret = "CLOUD_API_SECRET"
confluent_environment_id   = "env-xxxxx"
kafka_cluster_id           = "lkc-xxxxx"
kafka_api_key              = "KAFKA_API_KEY"
kafka_api_secret           = "KAFKA_API_SECRET"

# Oracle Connection
oracle_connection_host = "racnode-scan.example.com"  # Or AppGW IP
oracle_connection_port = 1521
oracle_username        = "jdbc_connector"
oracle_password        = "YourPassword123#"
oracle_db_name         = "pdb_name.domain.com"

# Table Selection
oracle_table_include_list          = "SCHEMA.TABLE1,SCHEMA.TABLE2"
oracle_mode                        = "timestamp+incrementing"
oracle_incrementing_column_mapping = "SCHEMA.TABLE1:[ID],SCHEMA.TABLE2:[ID]"
oracle_timestamp_columns_mapping   = "SCHEMA.TABLE1:[UPDATED_AT],SCHEMA.TABLE2:[UPDATED_AT]"

# Output Configuration
oracle_topic_prefix = "oracle-rac-"
```

**See [terraform.tfvars.oracle-connector.example](terraform.tfvars.oracle-connector.example) for complete configuration examples.**

### 3. Deploy

```bash
# Initialize Terraform (first time only)
terraform init

# Review planned changes
terraform plan

# Deploy AppGW and Oracle connector
terraform apply
```

### 4. Verify Deployment

```bash
# Check connector status
terraform output oracle_connector_status

# Get verification commands
terraform output oracle_connector_verification_commands

# Verify connector in Confluent Cloud
confluent connect cluster list
confluent connect cluster describe $(terraform output -raw oracle_connector_id)

# Check topics created
confluent kafka topic list | grep $(terraform output -raw oracle_connector_topic_prefix)
```

---

## Configuration Examples

### Example 1: Single Table - Timestamp+Incrementing

```hcl
create_oracle_connector = true

oracle_table_include_list          = "SALES.ORDERS"
oracle_mode                        = "timestamp+incrementing"
oracle_incrementing_column_mapping = "SALES.ORDERS:[ORDER_ID]"
oracle_timestamp_columns_mapping   = "SALES.ORDERS:[CREATED_AT]"
oracle_topic_prefix                = "sales-"
```

**Resulting topic:** `sales-SALES_ORDERS`

### Example 2: Multiple Tables - Different Columns

```hcl
oracle_table_include_list = "SALES.ORDERS,SALES.ORDER_ITEMS,INVENTORY.PRODUCTS"

oracle_incrementing_column_mapping = join(",", [
  "SALES.ORDERS:[ORDER_ID]",
  "SALES.ORDER_ITEMS:[ITEM_ID]",
  "INVENTORY.PRODUCTS:[PRODUCT_ID]"
])

oracle_timestamp_columns_mapping = join(",", [
  "SALES.ORDERS:[CREATED_AT]",
  "SALES.ORDER_ITEMS:[CREATED_AT]",
  "INVENTORY.PRODUCTS:[UPDATED_AT]"
])
```

**Resulting topics:**
- `oracle-rac-SALES_ORDERS`
- `oracle-rac-SALES_ORDER_ITEMS`
- `oracle-rac-INVENTORY_PRODUCTS`

### Example 3: High-Volume Configuration

```hcl
oracle_poll_interval_ms = 1000  # Poll every 1 second
oracle_batch_max_rows   = 500   # Larger batches
oracle_tasks_max        = 2     # Multiple tasks for parallelism
```

### Example 4: Timestamp-Only (No ID Column)

```hcl
oracle_table_include_list          = "AUDIT.EVENTS"
oracle_mode                        = "timestamp"
oracle_incrementing_column_mapping = ""  # Not used in timestamp mode
oracle_timestamp_columns_mapping   = "AUDIT.EVENTS:[EVENT_TIME]"
```

---

## Terraform Files

| File | Purpose |
|------|---------|
| `oracle-connector.tf` | Connector resource definition |
| `oracle-connector-variables.tf` | All Oracle connector variables |
| `oracle-connector-outputs.tf` | Connector status and verification commands |
| `terraform.tfvars.oracle-connector.example` | Configuration examples |

---

## Variables Reference

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `create_oracle_connector` | Enable/disable connector deployment | `true` |
| `confluent_cloud_api_key` | Cloud API key for deployment | `"CLOUD_API_KEY"` |
| `confluent_cloud_api_secret` | Cloud API secret | `"CLOUD_API_SECRET"` |
| `confluent_environment_id` | Environment ID | `"env-xxxxx"` |
| `kafka_cluster_id` | Kafka cluster ID | `"lkc-xxxxx"` |
| `kafka_api_key` | Kafka API key (for connector) | `"KAFKA_API_KEY"` |
| `kafka_api_secret` | Kafka API secret (for connector) | `"KAFKA_API_SECRET"` |
| `oracle_connection_host` | Oracle hostname or IP | `"racnode-scan.domain.com"` |
| `oracle_username` | Database username | `"jdbc_connector"` |
| `oracle_password` | Database password | `"Password123#"` |
| `oracle_db_name` | Database service name | `"pdb.domain.com"` |
| `oracle_table_include_list` | Tables to capture | `"SCHEMA.TABLE"` |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `oracle_connector_name` | `"oracle-rac-jdbc-source"` | Connector name |
| `oracle_connection_port` | `1521` | Oracle port |
| `oracle_mode` | `"timestamp+incrementing"` | CDC mode |
| `oracle_poll_interval_ms` | `5000` | Polling interval (ms) |
| `oracle_batch_max_rows` | `100` | Batch size |
| `oracle_tasks_max` | `1` | Number of tasks |
| `oracle_topic_prefix` | `"oracle-rac-"` | Topic name prefix |
| `oracle_output_data_format` | `"JSON"` | Output format (JSON/AVRO/PROTOBUF) |

**See [oracle-connector-variables.tf](oracle-connector-variables.tf) for complete list with validation rules.**

---

## Outputs

After deployment, Terraform provides:

```bash
# Connector ID
terraform output oracle_connector_id
# Output: lcc-xxxxx

# Connector status
terraform output oracle_connector_status
# Output: RUNNING

# Expected topics
terraform output oracle_connector_expected_topics
# Output: ["oracle-rac-SCHEMA_TABLE1", "oracle-rac-SCHEMA_TABLE2"]

# Verification commands
terraform output oracle_connector_verification_commands
# Output: Multi-line script with verification steps
```

---

## Troubleshooting

### Connector Shows FAILED Status

```bash
# Get detailed error
confluent connect cluster describe $(terraform output -raw oracle_connector_id)

# Common issues:
# 1. "Oracle Database server is unreachable"
#    → Check network connectivity from AppGW to Oracle
#    → Verify firewall rules allow TCP 1521

# 2. "Got minus one from a read call"
#    → Verify REMOTE_LISTENER uses FQDN, not IP
#    → Run: ALTER SYSTEM SET REMOTE_LISTENER='scan-name.domain:1521' SCOPE=BOTH;

# 3. "ORA-12514: TNS:listener does not currently know of service"
#    → Check oracle_db_name is fully qualified (pdb.domain.com)
#    → Verify service is registered: lsnrctl services
```

### Terraform Apply Fails

```bash
# Error: "Invalid credentials"
# → Check Cloud API key has correct permissions
# → Verify: confluent api-key list --resource cloud

# Error: "Kafka cluster not found"
# → Verify kafka_cluster_id exists in the environment
# → Check: confluent kafka cluster list --environment env-xxxxx

# Error: "depends_on reference error"
# → Ensure appgw-oracle-rac.tf is deployed first
# → Or remove depends_on if AppGW already exists
```

### Connector Deployed But No Data

```bash
# Check connector is actually polling
confluent connect cluster describe $(terraform output -raw oracle_connector_id)

# Verify table has data
# From Oracle:
SELECT COUNT(*) FROM <schema>.<table>;

# Check column mappings are correct
# incrementing column must be numeric and increasing
# timestamp column must be TIMESTAMP or DATE type

# Insert test record in Oracle
INSERT INTO <schema>.<table> VALUES (...);
COMMIT;

# Wait for poll interval (default 5 seconds)
# Check topic
confluent kafka topic consume <topic-name> --from-beginning
```

---

## Updating Connector Configuration

### Change Table Selection

```hcl
# Add more tables
oracle_table_include_list = "SCHEMA.TABLE1,SCHEMA.TABLE2,SCHEMA.TABLE3"

# Update column mappings
oracle_incrementing_column_mapping = "SCHEMA.TABLE1:[ID],SCHEMA.TABLE2:[ID],SCHEMA.TABLE3:[ID]"
oracle_timestamp_columns_mapping   = "SCHEMA.TABLE1:[UPDATED_AT],SCHEMA.TABLE2:[MODIFIED_AT],SCHEMA.TABLE3:[CREATED_AT]"
```

```bash
terraform apply
```

**Note:** Terraform will update the connector configuration. The connector will restart automatically.

### Change Polling Interval

```hcl
oracle_poll_interval_ms = 10000  # Change from 5s to 10s
```

```bash
terraform apply
```

### Pause Connector

```hcl
create_oracle_connector = false
```

```bash
terraform apply
# Connector will be deleted
```

To resume, set back to `true` and apply.

---

## Comparison: Terraform vs Manual Deployment

| Aspect | Terraform | Manual (Confluent CLI) |
|--------|-----------|------------------------|
| **Deployment** | `terraform apply` | `confluent connect cluster create --config-file ...` |
| **Configuration** | Version controlled in `.tf` files | JSON file, manual management |
| **Updates** | `terraform apply` (auto-detects changes) | `confluent connect cluster update` (manual) |
| **Secrets** | Terraform state (can use remote backend) | Environment variables or file |
| **Multi-environment** | Separate tfvars per environment | Separate JSON per environment |
| **Drift detection** | `terraform plan` shows differences | Manual comparison |
| **Rollback** | Git revert + `terraform apply` | Manual JSON restore + update |
| **Documentation** | Self-documenting infrastructure | Separate documentation |

**Recommendation:** Use Terraform for production deployments where:
- Multiple connectors need consistent configuration
- Configuration must be version controlled
- Automated CI/CD pipelines are used
- Multiple environments (dev/staging/prod) exist

Use manual deployment for:
- Quick testing and prototyping
- Single connector in development
- Learning and exploration

---

## Best Practices

### 1. Secrets Management

**Option A: Environment Variables**
```bash
export TF_VAR_oracle_password="YourPassword"
export TF_VAR_kafka_api_secret="KafkaSecret"
export TF_VAR_confluent_cloud_api_secret="CloudSecret"

terraform apply
```

**Option B: Separate tfvars file (gitignored)**
```bash
# .gitignore
terraform.tfvars.secrets

# terraform.tfvars.secrets
oracle_password              = "YourPassword"
kafka_api_secret             = "KafkaSecret"
confluent_cloud_api_secret   = "CloudSecret"

# Deploy with both files
terraform apply -var-file=terraform.tfvars -var-file=terraform.tfvars.secrets
```

**Option C: Remote state with encryption**
```hcl
terraform {
  backend "azurerm" {
    storage_account_name = "tfstate"
    container_name       = "terraform"
    key                  = "oracle-connector.tfstate"
    use_azuread_auth     = true
  }
}
```

### 2. Multiple Environments

```bash
# Directory structure
terraform.tfvars.dev
terraform.tfvars.staging
terraform.tfvars.prod

# Deploy to dev
terraform workspace new dev
terraform apply -var-file=terraform.tfvars.dev

# Deploy to prod
terraform workspace new prod
terraform apply -var-file=terraform.tfvars.prod
```

### 3. Version Pinning

```hcl
terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "= 1.51.0"  # Pin to specific version
    }
  }
}
```

---

## Summary

✅ **Terraform Deployment** - Automate Oracle connector alongside AppGW  
✅ **Version Control** - Track configuration changes in Git  
✅ **Consistent Environments** - Dev, staging, prod parity  
✅ **Drift Detection** - `terraform plan` shows configuration drift  
✅ **Outputs** - Automatic verification commands  

**Next Steps:**
1. Copy variables from [terraform.tfvars.oracle-connector.example](terraform.tfvars.oracle-connector.example)
2. Configure your Oracle connection details
3. Run `terraform apply`
4. Verify with `terraform output oracle_connector_verification_commands`

For manual deployment, see [ORACLE-RAC-QUICKSTART.md](ORACLE-RAC-QUICKSTART.md).
