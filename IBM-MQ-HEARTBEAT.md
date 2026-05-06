# IBM MQ Heartbeat and Application Gateway Idle Timeout Configuration

## Critical Configuration for Long-Lived Connections

When using IBM MQ with Azure Application Gateway for long-lived connections, proper alignment of idle timeouts and heartbeat intervals is **critical** to prevent connection drops during periods of queue inactivity.

## The Problem

**Scenario**: No messages on the queue for extended periods

When an IBM MQ queue has no messages, the connection between the Confluent connector and IBM MQ becomes idle. If this idle period exceeds the Application Gateway's idle timeout, the gateway will close the connection, causing:

- Connection failures in the connector
- Reconnection storms
- Message processing delays
- Connector task failures

## The Solution: Aligned Timeouts

Configure the system with these relationships:

```
IBM MQ Heartbeat Interval < Application Gateway Idle Timeout
```

**Example Safe Configuration**:
- Application Gateway Idle Timeout: **15 minutes** (default in this setup)
- IBM MQ Client Heartbeat Interval: **5 minutes** (300 seconds)

This ensures heartbeat traffic keeps the connection alive well before the AppGW timeout.

## Application Gateway Configuration

### Default Settings (This Terraform Configuration)

```hcl
# variables.tf
variable "appgw_idle_timeout_minutes" {
  description = "Application Gateway idle timeout in minutes (1-20)"
  type        = number
  default     = 15  # 15 minutes
}
```

### Customizing the Idle Timeout

To change the Application Gateway idle timeout, set in `terraform.tfvars`:

```hcl
# Increase to 20 minutes for very infrequent message scenarios
appgw_idle_timeout_minutes = 20

# Or reduce to 10 minutes if heartbeat overhead is a concern
appgw_idle_timeout_minutes = 10
```

**Important Constraints**:
- Minimum: 1 minute
- Maximum: 20 minutes (Azure limitation)
- Recommended: 10-15 minutes for IBM MQ

### Where It's Applied

The idle timeout is configured on the Application Gateway backend settings:

```hcl
# main.tf - IBM MQ Backend Settings
backend {
  name                     = "ibm-mq-backend-settings"
  port                     = var.ibm_mq_backend_port
  protocol                 = "Tcp"
  timeout_in_seconds       = 20  # Request timeout (different from idle)
  idle_timeout_in_minutes  = var.appgw_idle_timeout_minutes  # Idle timeout
  probe_name               = "ibm-mq-health-probe"
}
```

**Note**: Don't confuse these two timeout settings:
- `timeout_in_seconds` (20s): Time to wait for initial response to a request
- `idle_timeout_in_minutes` (15m): Time before closing an idle established connection

## IBM MQ Client Heartbeat Configuration

### Understanding IBM MQ Heartbeats

IBM MQ Java clients (used by the Confluent connector) support heartbeat intervals to keep connections alive. The heartbeat is implemented through the `HBINT` (Heartbeat Interval) channel attribute.

### Server-Side Configuration (IBM MQ Server)

Configure the heartbeat interval on the IBM MQ server connection channel:

```bash
# Set heartbeat interval to 300 seconds (5 minutes)
# This is LESS than the AppGW idle timeout of 15 minutes
ALTER CHANNEL(DEV.APP.SVRCONN) CHLTYPE(SVRCONN) HBINT(300)

# Or when creating a new channel
DEFINE CHANNEL(CONFLUENT.CHL) CHLTYPE(SVRCONN) HBINT(300) TRPTYPE(TCP) MCAUSER('confluent')
```

**HBINT Values**:
- Value in seconds
- `0` = No heartbeat (not recommended with AppGW)
- Recommended: `300` (5 minutes) for AppGW idle timeout of 15 minutes
- Maximum: Depends on your version, typically up to 999999 seconds

### Client-Side Configuration (Confluent Connector)

The IBM MQ Java client used by the Confluent connector typically inherits the heartbeat interval from the server-side channel configuration. However, you can also set client-side properties.

#### Option 1: Using IBM MQ Environment Variables (Recommended)

Set environment variables on the IBM MQ server or client system:

```bash
# Set client heartbeat interval to 300 seconds (5 minutes)
export MQIKEPALIVEINTERVAL=300
```

#### Option 2: Using JMS Connection Factory Properties

If you have control over the connector's JMS configuration, you can set:

```properties
# In the connector configuration (if exposed)
heartbeat.interval=300
```

**Note**: The Confluent IBM MQ Source connector may not directly expose heartbeat configuration. In this case, rely on the server-side `HBINT` setting, which the client will honor.

### Verifying Heartbeat Configuration

Check the channel configuration on IBM MQ:

```bash
# Display channel heartbeat interval
DISPLAY CHANNEL(DEV.APP.SVRCONN) HBINT

# Expected output:
# HBINT(300)
```

Monitor active connections to verify heartbeats are working:

```bash
# Display active connections
DISPLAY CONN(*) WHERE(CHANNEL EQ DEV.APP.SVRCONN)

# Look for heartbeat-related fields in the output
```

## Recommended Configurations by Use Case

### High-Frequency Queues (Messages every few seconds)

When messages flow frequently, heartbeats are less critical but still recommended:

```hcl
# terraform.tfvars
appgw_idle_timeout_minutes = 10
```

```bash
# IBM MQ Server
ALTER CHANNEL(DEV.APP.SVRCONN) HBINT(180)  # 3 minutes
```

### Medium-Frequency Queues (Messages every few minutes)

Standard configuration for most scenarios:

```hcl
# terraform.tfvars
appgw_idle_timeout_minutes = 15  # Default
```

```bash
# IBM MQ Server
ALTER CHANNEL(DEV.APP.SVRCONN) HBINT(300)  # 5 minutes
```

### Low-Frequency Queues (Messages hourly or less)

For queues with very infrequent messages:

```hcl
# terraform.tfvars
appgw_idle_timeout_minutes = 20  # Maximum allowed
```

```bash
# IBM MQ Server
ALTER CHANNEL(DEV.APP.SVRCONN) HBINT(600)  # 10 minutes
```

## Monitoring and Troubleshooting

### Symptoms of Misconfigured Timeouts

**Connection Drops During Idle Periods**:
```
Error: MQJE001: Completion Code '2', Reason '2009'
(Connection broken)
```

**Frequent Reconnections**:
- Check connector logs for repeated connection attempts
- Look for "Connection reset" or "Connection timed out" errors

**Application Gateway Logs**:
```bash
# Check App Gateway backend health
az network application-gateway show-backend-health \
  --name <appgw-name> \
  --resource-group <rg-name>
```

### Verification Steps

1. **Check AppGW Idle Timeout**:
   ```bash
   # View the current configuration
   terraform output
   
   # Or query Azure directly
   az network application-gateway show \
     --name <appgw-name> \
     --resource-group <rg-name> \
     --query "backendSettingsPools[0].idleTimeoutInMinutes"
   ```

2. **Check IBM MQ Heartbeat Interval**:
   ```bash
   # On IBM MQ server
   echo "DISPLAY CHANNEL(DEV.APP.SVRCONN) HBINT" | runmqsc QM1
   ```

3. **Test with No Messages**:
   - Stop sending messages to the queue
   - Monitor connector status for 20+ minutes
   - Verify connection remains active

### Common Issues

#### Issue: Connection drops after exactly 4 minutes

**Cause**: Default Azure Application Gateway idle timeout (240 seconds)

**Solution**: Ensure `appgw_idle_timeout_minutes` is set and Terraform has been applied:
```bash
terraform apply
```

#### Issue: Heartbeat not working

**Cause**: HBINT set to 0 or not configured

**Solution**: Verify and set HBINT on the IBM MQ channel:
```bash
ALTER CHANNEL(DEV.APP.SVRCONN) HBINT(300)
REFRESH SECURITY TYPE(CONNAUTH)
```

#### Issue: Heartbeat interval too long

**Cause**: HBINT > AppGW idle timeout

**Solution**: Reduce HBINT to be less than AppGW timeout:
```bash
# If AppGW timeout is 15 minutes (900 seconds)
ALTER CHANNEL(DEV.APP.SVRCONN) HBINT(300)  # Set to 5 minutes
```

## Best Practices

### 1. Conservative Heartbeat Intervals

Set heartbeat interval to **30-50%** of the AppGW idle timeout:

```
AppGW Idle Timeout: 15 minutes (900 seconds)
→ Heartbeat Interval: 5 minutes (300 seconds) = 33%
```

This provides a safety margin for network delays and processing latency.

### 2. Test During Deployment

Include idle period testing in your deployment validation:

```bash
# After deploying the connector, test with no messages
# Wait for (AppGW timeout + 5 minutes) to verify connection stability
# Expected: No connection drops in connector logs
```

### 3. Monitor Both Sides

- **Azure Application Gateway**: Monitor backend health and connection counts
- **IBM MQ**: Monitor active connections and channel status
- **Confluent Connector**: Monitor connector task status and error logs

### 4. Document Your Configuration

When you customize timeouts, document them:

```hcl
# terraform.tfvars
# Custom timeout for low-frequency queue (messages every 2-3 hours)
# Heartbeat configured on IBM MQ channel: HBINT(600)
appgw_idle_timeout_minutes = 20
```

### 5. Align Across All Layers

Remember the full connection path:

```
Confluent Connector → Confluent Egress → Azure Private Link → 
Application Gateway → IBM MQ Server
```

Each layer can have timeout settings:
- **Confluent Cloud**: Default egress endpoint timeout (typically 30 minutes)
- **Azure Private Link**: No idle timeout (connection passes through)
- **Application Gateway**: `idle_timeout_in_minutes` (configurable, 1-20 min)
- **IBM MQ Server**: `HBINT` channel heartbeat (configurable)

The **most restrictive timeout in the chain determines behavior**. In this setup, AppGW is typically the limiting factor.

## Summary

| Configuration | Value | Purpose |
|--------------|-------|---------|
| AppGW Idle Timeout | 15 minutes (default) | Maximum idle time before connection close |
| IBM MQ HBINT | 300 seconds (5 min) | Heartbeat to keep connection alive |
| Relationship | HBINT < AppGW Timeout | Ensures heartbeat fires before timeout |
| Safety Margin | 3x (HBINT × 3 < Timeout) | Accounts for delays and retries |

## Quick Start Checklist

- [ ] Set `appgw_idle_timeout_minutes` in `terraform.tfvars` (default: 15)
- [ ] Apply Terraform configuration: `terraform apply`
- [ ] Configure IBM MQ channel heartbeat: `ALTER CHANNEL(...) HBINT(300)`
- [ ] Verify: `HBINT < (appgw_idle_timeout_minutes × 60)`
- [ ] Test with no messages for extended period
- [ ] Monitor connector logs for connection stability

## Additional Resources

- [Azure Application Gateway Timeouts](https://learn.microsoft.com/en-us/azure/application-gateway/application-gateway-faq)
- [IBM MQ Heartbeat Configuration](https://www.ibm.com/docs/en/ibm-mq/9.3?topic=reference-heartbeat-interval-hbint)
- [Confluent IBM MQ Source Connector](https://docs.confluent.io/kafka-connectors/ibm-mq-source/current/overview.html)
