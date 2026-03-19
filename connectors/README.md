# ⚠️ DEPRECATED: Scripted Connector Deployment

This directory contains the **legacy scripted approach** for deploying the IBM MQ Source connector.

## 🆕 New Approach: Terraform Deployment

The connector is now deployed automatically via Terraform. See the main [README.md](../README.md) for instructions.

### Quick Migration

Instead of using `generate-config.sh`, configure the connector in `terraform.tfvars`:

```hcl
# Enable connector deployment
create_connector = true

# Configure connector settings
kafka_cluster_id     = "lkc-xxxxx"
kafka_api_key        = "YOUR_KEY"
kafka_api_secret     = "YOUR_SECRET"
kafka_topic          = "ibm-mq-messages"

# IBM MQ settings
mq_queue_manager     = "QM1"
mq_channel           = "DEV.APP.SVRCONN"
jms_destination_name = "DEV.QUEUE.1"

# Optional: credentials
mq_username = "mqadmin"
mq_password = "your-password"
```

Then run:
```bash
terraform apply
```

The connector will be created automatically and use the correct network and hostname (DNS or IP).

## Legacy Files

These files are kept for reference but are no longer the recommended approach:

- `ibm-mq-source.json` - Connector template (now in Terraform)
- `ibm-mq-source.env.example` - Environment variables (now in terraform.tfvars)
- `generate-config.sh` - Configuration generator (replaced by Terraform)

**For new deployments, please use the Terraform approach documented in the main README.**
