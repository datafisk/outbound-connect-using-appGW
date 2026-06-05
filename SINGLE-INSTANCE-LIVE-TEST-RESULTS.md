# Single-Instance RAC Live Testing - Connector Behavior Results

## Test Overview

**Objective:** Test actual connector behavior in single-instance RAC scenario by pausing and resuming connector to force new database connections.

**Date:** 2026-06-05

**Scenario:** System already in single-instance state based on Azure VM testing showing ORA-12514 on backends.

---

## Pre-Test State

**From Azure VM Testing (2026-06-04):**
- racnode1-vip (10.99.1.165): 50% ORA-12514, 50% timeout
- racnode2-vip (10.99.1.84): 100% ORA-12514
- AppGW (172.200.9.19): 70% ORA-12514, 30% connection closed

**Connector Status Before Test:**
```
Status: RUNNING
Task State: RUNNING
```

**AppGW Configuration:**
```
Backend Pool: [10.99.1.165, 10.99.1.84]
Both VIPs in pool despite ORA-12514 on backends
```

---

## Test Procedure

### Phase 1: Pause Connector

**Action:** Paused connector to disconnect active database connections

**Result:**
```
Status: PAUSED
Task State: STOPPED
```

### Phase 2: Resume Connector (Forcing Reconnection)

**Action:** Attempted to resume connector, forcing new database connections through AppGW

**Result:** Connector FAILED to resume

**Status After Multiple Resume Attempts:**
```
Status: PAUSED (remains paused)
Task State: STOPPED
Configuration Validation: FAILED
Error: "Could not connect to database"
```

**Observation:** Despite multiple resume attempts over 5+ minutes, connector remained in PAUSED state unable to establish new connections.

---

## Key Findings

### 1. Established Connections Work, New Connections Fail

**Before Pause:**
- Connector: RUNNING
- Connections: Established and maintained
- Data flowing successfully

**After Pause:**
- Connector: Cannot resume
- New connections: Fail validation
- Error: Cannot connect to database

**Conclusion:** Existing database connections persist and work, but establishing NEW connections through AppGW with ORA-12514 backends fails.

### 2. Connector Cannot Recover from Restart

**Implication:** If connector needs to restart (maintenance, failure, configuration change), it cannot reconnect when backends return ORA-12514.

**Scenarios Affected:**
- Connector restart/redeploy
- Configuration updates requiring restart
- Cluster maintenance requiring connector pause
- Automatic failover scenarios

### 3. Configuration Validation Blocks Resume

**Error Message:**
```
Unable to validate configuration. Could not connect to database.
Connector continues to operate on previous configuration that passed validation.
```

**Analysis:**
- Confluent Cloud validates connector configuration before resuming
- Validation attempts database connection
- Connection attempts hit ORA-12514 backends through AppGW
- Validation fails, blocking connector resume

---

## Why Connector Was Working Initially

**Theory:** Connector established connections when both RAC instances had service registered, or connected during a window when AppGW routed to working backend.

**Once Established:**
- Database connections are long-lived
- Connection pooling maintains active connections
- Connector doesn't create new connections frequently
- Existing connections bypass the ORA-12514 issue

**Problem Surfaces When:**
- Connector restarts (new connections required)
- Connection pool refresh (new connections needed)
- Configuration changes (forces reconnection)

---

## Technical Analysis

### Connection Lifecycle

**Successful Startup (Original):**
```
1. Connector starts
2. Attempts connection through AppGW
3. AppGW routes to working backend (luck or timing)
4. Connection established
5. Connection persists
6. Connector RUNNING
```

**Failed Resume (After Pause):**
```
1. Connector attempts resume
2. Validates configuration
3. Attempts connection through AppGW
4. AppGW routes to backend with ORA-12514 (70% probability)
5. Connection validation fails
6. Connector remains PAUSED
```

### Why Retry Doesn't Help

**Multiple Resume Attempts:**
- Each attempt routes through AppGW
- AppGW load-balances across both VIPs
- 70% probability of hitting ORA-12514 backend
- No guarantee of successful connection
- Validation fails repeatedly

---

## Implications

### Production Impact

**Risk Scenarios:**

1. **Connector Restart Required**
   - Configuration change
   - Confluent Cloud maintenance
   - Connector failure/crash
   - Result: **Cannot resume**

2. **Connection Pool Refresh**
   - Periodic connection renewal
   - May hit ORA-12514 backend
   - Result: **Intermittent failures**

3. **Scaling Events**
   - Tasks scale up/down
   - New tasks create new connections
   - Result: **Unpredictable success rate**

### Availability Impact

**Current State:** Connector appears healthy (RUNNING)

**Reality:** Fragile state that cannot recover from restart

**Recovery:** Requires manual intervention or backend configuration fix

---

## Solutions

### Immediate Fix (Restore Connector)

To restore connector to RUNNING state:

**Option 1: Fix Backend Pool**
```bash
# Remove VIP with ORA-12514 from backend pool temporarily
az network application-gateway address-pool update \
  -g <resource-group> \
  --gateway-name <appgw-name> \
  -n oracle_rac_oci \
  --servers <working_vip_only>

# Resume connector
confluent connect cluster resume <connector-id> --environment <env-id>

# Wait for RUNNING state
# Restore both VIPs after service fixed
```

**Option 2: Update Connector Configuration**
```bash
# Update connector to use direct VIP (bypass AppGW temporarily)
# Then resume
# Restore AppGW routing after backend fixed
```

### Long-Term Solution

**Configure Service on Both RAC Instances:**
```sql
-- Ensure service registered on both instances
srvctl add service -d <database> -s <service> \
  -preferred instance1,instance2
srvctl start service -d <database> -s <service>

-- Verify registration
SELECT service_name, inst_id FROM gv$services 
WHERE service_name = '<service>';
```

**Result:**
- Both VIPs serve database connections
- No ORA-12514 errors
- Connector can resume successfully
- True high availability enabled

---

## Validation Steps

**After Fixing Backend:**

1. **Verify Service Registration**
   ```sql
   SELECT service_name, inst_id, host_name 
   FROM gv$services 
   WHERE service_name = '<your_service>';
   ```
   Expected: Service on both inst_id values

2. **Test Connections**
   ```bash
   # From Azure VM or test client
   sqlplus user/pass@<vip1>:1521/<service>  # Should succeed
   sqlplus user/pass@<vip2>:1521/<service>  # Should succeed
   ```

3. **Resume Connector**
   ```bash
   confluent connect cluster resume <connector-id> --environment <env-id>
   ```
   Expected: Status transitions to RUNNING

4. **Monitor Stability**
   ```bash
   # Check status for 5-10 minutes
   watch -n 30 "confluent connect cluster describe <connector-id> --environment <env-id> | grep Status"
   ```
   Expected: Remains RUNNING

---

## Conclusions

### Empirical Evidence

1. **Existing Connections Persist:** Connector was RUNNING despite ORA-12514 backends
2. **New Connections Fail:** Connector cannot resume after pause
3. **No Automatic Recovery:** Multiple resume attempts fail
4. **Configuration Validation Blocks:** Cannot validate config with failing backends

### Key Takeaway

**The single-instance RAC scenario creates a "works until restart" situation:**
- Connector appears healthy when running
- Cannot recover from any restart/pause event
- Requires manual intervention to restore
- Production reliability significantly impacted

### Recommendations

**For Existing Single-Instance Deployments:**
1. Avoid connector restarts until backends fixed
2. Do not pause connector for maintenance
3. Monitor connection health proactively
4. Plan service configuration on both nodes

**For New Deployments:**
1. Always configure service on ALL RAC instances
2. Verify service registration before deploying connector
3. Test pause/resume before production
4. Use single VIP only as temporary workaround

---

## Related Documentation

- [Azure VM Testing Results](AZURE-VM-TESTING-RESULTS.md) - Empirical ORA-12514 evidence
- [Single-Instance RAC Findings](SINGLE-INSTANCE-RAC-FINDINGS.md) - Technical analysis
- [Oracle RAC HA Testing](ORACLE-RAC-HA-TESTING.md) - High availability validation

---

**Test Date:** 2026-06-05  
**Key Result:** Connector cannot resume after pause when backends return ORA-12514  
**Status:** Connector requires manual recovery
