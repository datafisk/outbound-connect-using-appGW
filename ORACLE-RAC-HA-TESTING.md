# Oracle RAC High Availability Testing with Azure Application Gateway and Confluent Cloud

## Overview

This document summarizes comprehensive high availability testing of Confluent Cloud Oracle JDBC Source Connector using Azure Application Gateway as a Layer 4 TCP proxy to Oracle Real Application Clusters (RAC).

## Configuration Overview

**Backend Pool Configuration:**
- **Before:** Physical node IPs (no automatic failover)
- **After:** Virtual IP (VIP) addresses (RAC failover enabled)
- **AppGW Idle Timeout:** 900 seconds (15 minutes)

**Key Components:**
- Azure Application Gateway with TCP backend settings
- Oracle RAC 2-node cluster on Oracle Cloud Infrastructure (OCI)
- Confluent Cloud Oracle JDBC Source Connector
- VNet peering between Azure and OCI

---

## Test 1: Single-Node Failover (VIP Migration)

### Procedure

1. Oracle RAC cluster fully operational, connector status RUNNING
2. Stopped one RAC node hosting an active VIP
3. Monitored connector for 5+ minutes
4. Restarted failed node

### Results

- ✅ **Zero downtime** - Connector remained RUNNING throughout
- ✅ **Seamless VIP migration** - VIP automatically relocated to surviving node
- ✅ **Transparent failover** - No connection errors or interruptions
- ✅ **Application Gateway health probes** continued functioning as VIP moved

### Conclusion

VIP-based backend pool configuration provides true RAC high availability with automatic node-level failover.

---

## Test 2: Complete Cluster Failure and Auto-Recovery

### Procedure

1. Connector RUNNING, both RAC nodes operational
2. Stopped both RAC nodes simultaneously (complete cluster outage)
3. Monitored connector failure behavior
4. Restarted both RAC nodes
5. Monitored for auto-recovery without manual intervention

### Timeline

| Time | Event |
|------|-------|
| **T+0:00** | Monitoring started, cluster shutdown initiated |
| **T+1:00** | Connector transitioned to FAILED state<br>Status: FAILED<br>Task State: USER_ACTIONABLE_ERROR |
| **T+5:00** | Both RAC nodes became AVAILABLE |
| **T+11:00** | Connector AUTO-RECOVERED<br>Status: RUNNING<br>Task State: RUNNING |

### Recovery Metrics

- **Time from failure to recovery:** ~11 minutes
- **Time to auto-recover after cluster restoration:** ~6 minutes
- **Manual intervention required:** NONE

---

## Important Finding: "Unrecoverable Exception" That Recovers

During complete cluster failure, the connector logs show an "uncaught and unrecoverable exception":

```
WorkerSourceTask{id=<connector-id>} Task threw an uncaught and unrecoverable 
exception. Task is being killed and will not recover until manually restarted

org.apache.kafka.connect.errors.ConnectException: Error while polling for records
...
Caused by: java.sql.SQLRecoverableException: Listener refused the connection 
with the following error:
ORA-12514, TNS:listener does not currently know of service requested in connect 
descriptor
...
Caused by: oracle.net.ns.NetException: Listener refused the connection with the 
following error:
ORA-12514, TNS:listener does not currently know of service requested in connect 
descriptor
```

### Key Observation

Despite the log message stating "will not recover until manually restarted," the connector **DOES automatically recover** once the Oracle RAC cluster is restored. The Confluent Cloud orchestration layer handles the recovery automatically.

### Recovery Behavior

1. Connector throws `ConnectException` with `SQLRecoverableException`
2. Task state changes to `USER_ACTIONABLE_ERROR`
3. Connector framework continues retry logic
4. After cluster restoration (~6 minutes), connector automatically resumes
5. No manual restart required

---

## Results Summary

### Single-Node Failures

- ✅ **Zero downtime** with VIP-based configuration
- ✅ **Automatic VIP relocation** to surviving node
- ✅ **No connection interruption**

### Complete Cluster Failures

- ✅ **Graceful degradation** - Connector transitions to FAILED state
- ✅ **Automatic recovery** after cluster restoration
- ✅ **Recovery time:** ~6 minutes after cluster becomes available
- ✅ **No manual intervention needed**

---

## Best Practices and Recommendations

### Backend Pool Configuration

1. **Use Virtual IP addresses** (not physical node IPs) in Application Gateway backend pools
   - Enables automatic RAC failover
   - VIPs relocate to surviving nodes during failures
   
2. **Application Gateway Timeout Settings**
   - Idle timeout: 900 seconds (15 minutes) minimum
   - Accommodates long-lived database connections
   - Supports extended query execution times

3. **Health Probe Configuration**
   - Protocol: TCP
   - Port: Database listener port (typically 1521)
   - Interval: 30 seconds
   - Timeout: 10 seconds
   - Unhealthy threshold: 3

### Operational Guidelines

#### Single-Node Failures

- No action required - automatic failover occurs
- Monitor for VIP relocation confirmation
- Verify connector remains RUNNING

#### Complete Cluster Failures

- Expected behavior: Connector transitions to FAILED
- Wait ~6 minutes after cluster restoration
- Monitor for automatic recovery to RUNNING state
- **Do not manually restart** - let auto-recovery complete

#### Monitoring

- Monitor connector status: RUNNING = healthy
- Task state: RUNNING = normal, USER_ACTIONABLE_ERROR = temporary failure
- Ignore "unrecoverable exception" messages during known outages
- Recovery is automatic despite log message stating otherwise

### Why VIP Configuration Over Physical IPs

| Configuration | Single-Node Failure | Complete Cluster Failure |
|--------------|---------------------|--------------------------|
| **Physical Node IPs** | Connection lost, no failover | Connector fails, auto-recovers |
| **Virtual IPs (VIPs)** | Zero downtime, automatic failover | Connector fails, auto-recovers |

**Recommendation:** Always use VIP addresses to enable RAC high availability features.

---

## Connector Resilience Characteristics

1. **Retry Logic:** Built-in retry mechanism for transient failures
2. **Recovery Window:** ~6 minutes after backend becomes available
3. **No Manual Restart Required:** Confluent Cloud orchestration handles recovery
4. **Error Tolerance:** Gracefully handles `SQLRecoverableException` and `ORA-12514` errors

---

## Technical Details

### Oracle Listener Architecture

In Oracle RAC, there are three types of listeners:

1. **SCAN Listeners** (on SCAN VIP addresses)
   - Handle initial connection requests via SCAN DNS name
   - Redirect clients to node-specific listeners
   - Confluent Cloud External Access Points (EAP) cannot follow TNS redirects

2. **Node Listeners** (on node VIP addresses)
   - Each RAC node has a listener on its VIP
   - Handle actual database connections
   - Provide failover capability - if node fails, VIP relocates to surviving node

3. **Node Listeners on Physical IPs** (optional)
   - Some RAC installations have listeners on physical node IPs
   - Works but bypasses RAC failover mechanism

### AppGW Backend Configuration for RAC

**Bypassing SCAN Redirect:**
- Configure AppGW backend pool with VIP addresses directly
- Bypasses SCAN listener and TNS redirect mechanism
- Maintains RAC failover capability through VIP relocation
- Compatible with Confluent Cloud EAP architecture

**Example Configuration:**
```hcl
backend_address_pool {
  name         = "oracle_rac_pool"
  ip_addresses = ["<vip1_ip>", "<vip2_ip>"]  # Use VIP IPs, not physical IPs
}

backend {
  name               = "oracle_backend"
  port               = 1521
  protocol           = "Tcp"
  timeout_in_seconds = 900  # 15 minutes
  probe_name         = "oracle_health_probe"
}

probe {
  name                = "oracle_health_probe"
  protocol            = "Tcp"
  port                = 1521
  interval            = 30
  timeout             = 10
  unhealthy_threshold = 3
}
```

---

## Conclusion

Oracle JDBC Source Connector with Azure Application Gateway using VIP-based backend pools provides:

- **High Availability:** Zero downtime during single-node failures
- **Automatic Failover:** VIP relocation transparent to connector
- **Self-Healing:** Auto-recovery after complete cluster restoration
- **Production Ready:** Validated resilience for enterprise deployments

### Key Takeaway

Despite "unrecoverable exception" log messages during outages, the connector automatically recovers without manual intervention once the Oracle RAC cluster is restored (~6 minute recovery time).

### When to Take Action

**No action needed:**
- Single-node failures (automatic VIP failover)
- Complete cluster failures with automatic recovery within 6-10 minutes

**Action required:**
- Connector remains FAILED for more than 15 minutes after cluster restoration
- Persistent USER_ACTIONABLE_ERROR after normal recovery window
- Repeated failures indicating configuration issues

---

## Related Documentation

- [Oracle RAC Quick Start](ORACLE-RAC-QUICKSTART.md)
- [Oracle RAC AppGW Setup](ORACLE-RAC-APPGW-SETUP.md)
- [Oracle Connector Terraform Configuration](ORACLE-CONNECTOR-TERRAFORM.md)
- [Repository README](README.md)
