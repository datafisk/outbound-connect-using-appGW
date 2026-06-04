# Test Plan: Single-Instance Database on 2-Node RAC Cluster

## Customer Scenario

**Setup:**
- 2-node Oracle RAC cluster
- Single-instance database (not using both nodes)
- Database service registered ONLY on one node's listener
- Other node's listener returns ORA-12514

**Example from customer:**
```
Node 1 (.40): Listener running, but ORA-12514 (service not registered)
Node 2 (.41): Listener running, service registered, connections succeed
SCAN: Redirects all clients to .41
```

## The Question

If we configure Azure Application Gateway backend pool with both VIPs:
1. Will AppGW load-balance ~50% of connections to the "wrong" VIP?
2. Will those connections fail with ORA-12514?
3. Will the Oracle JDBC driver gracefully retry the other VIP?
4. Will the connector work reliably, or will it fail intermittently?

## Expected Behavior Analysis

### AppGW Health Probe Limitation

**Problem:**
- AppGW health probes use TCP protocol only
- TCP probe checks if port 1521 accepts connections
- Both node listeners are RUNNING and accept TCP connections
- AppGW marks both backends as HEALTHY
- ORA-12514 is a TNS/application-layer error, not TCP-layer
- AppGW cannot detect ORA-12514

**Result:** Both VIPs appear healthy to AppGW, even though only one has the database service.

### Load Balancing Behavior

**AppGW will:**
1. Mark both VIPs as healthy (TCP probe succeeds)
2. Load-balance connections between both VIPs
3. Route ~50% of new connections to each VIP

**Connection Outcomes:**
- Connections to "correct" VIP (.41): SUCCESS
- Connections to "wrong" VIP (.40): ORA-12514

### JDBC Driver Retry Behavior

**When connector gets ORA-12514:**
1. Oracle JDBC driver classifies as `SQLRecoverableException`
2. Connector framework retry logic activates
3. **BUT:** Retry goes back through AppGW
4. AppGW may route retry to .40 again → another ORA-12514
5. No guarantee of routing to .41

**Likely outcome:** Intermittent failures with unpredictable retry success.

## Test Plan

### Phase 1: Verify Current Service Registration

**Objective:** Determine which nodes currently have the database service registered.

**Steps:**
1. Connect to both RAC nodes via SSH
2. Check listener status on each node:
   ```bash
   lsnrctl status
   ```
3. Query database for service registration:
   ```sql
   SELECT s.service_name, i.instance_name, i.host_name
   FROM gv$services s, gv$instance i
   WHERE s.inst_id = i.inst_id
   ORDER BY s.service_name, i.instance_name;
   ```

**Expected:** Service likely registered on both nodes (standard RAC configuration).

### Phase 2: Simulate Single-Instance Configuration

**Objective:** Configure database service to be registered on only ONE node.

**Steps:**
1. Identify target service (e.g., XSTREAMPDB)
2. Stop service on racnode1 (keep on racnode2):
   ```sql
   -- Connect to racnode1 instance
   ALTER SYSTEM SET service_names='';
   ```
3. Verify service registration:
   ```bash
   # On racnode1
   lsnrctl services | grep -i xstreampdb
   # Should show: ORA-12514 or service not found
   
   # On racnode2
   lsnrctl services | grep -i xstreampdb
   # Should show: Service registered
   ```

### Phase 3: Test AppGW with Both VIPs

**Objective:** Verify AppGW behavior with both VIPs in backend pool when service is only on one node.

**Current Configuration:**
```
Backend Pool: [racnode1-vip: .165, racnode2-vip: .84]
Service: Only on racnode2-vip (.84)
```

**Test Steps:**
1. Verify connector is currently RUNNING
2. Monitor connector for 10 minutes
3. Restart connector to force new connections
4. Watch for ORA-12514 errors in connector logs
5. Track success/failure rate

**Monitoring Commands:**
```bash
# Monitor connector status
watch -n 5 "confluent connect cluster describe <connector-id> --environment <env-id>"

# Check for ORA-12514 in connector logs (if accessible)
# Look for: "ORA-12514, TNS:listener does not currently know of service"
```

**Expected Results:**
- ⚠️  Intermittent ORA-12514 errors
- ⚠️  Connector may fail to start or transition to FAILED
- ⚠️  Unpredictable connection success rate

### Phase 4: Test AppGW with Single VIP (Solution)

**Objective:** Verify that using only the "correct" VIP eliminates ORA-12514 errors.

**Configuration Change:**
```bash
# Remove racnode1-vip (.165) from backend pool
az network application-gateway address-pool update \
  -g <resource-group> \
  --gateway-name <appgw-name> \
  -n oracle_rac_oci \
  --servers 10.99.1.84  # Only racnode2-vip
```

**Test Steps:**
1. Update backend pool to only include racnode2-vip (.84)
2. Restart connector
3. Monitor for 10 minutes
4. Verify no ORA-12514 errors

**Expected Results:**
- ✅ All connections succeed
- ✅ No ORA-12514 errors
- ✅ Connector remains RUNNING

### Phase 5: Test Failover Behavior (Single VIP)

**Objective:** Verify what happens if the node with the service fails.

**Scenario:**
```
Backend Pool: [racnode2-vip: .84 only]
Service: Only on racnode2
Action: Stop racnode2
```

**Test Steps:**
1. Configure backend pool with only racnode2-vip (.84)
2. Stop racnode2 node
3. Monitor connector behavior

**Expected Results:**
- ❌ VIP .84 does NOT relocate (service not configured for failover)
- ❌ Connector fails with connection errors
- ❌ No automatic recovery until racnode2 restarts

**This reveals the limitation:** Single-instance DB on RAC loses HA benefits.

## Solutions and Recommendations

### Solution 1: Single VIP in Backend Pool (Customer Workaround)

**Configuration:**
```
Backend Pool: [Only the VIP where service is registered]
```

**Pros:**
- ✅ Eliminates ORA-12514 errors
- ✅ Predictable connection behavior

**Cons:**
- ❌ No automatic failover if that node fails
- ❌ Manual intervention required if service moves
- ❌ Defeats RAC high availability purpose

### Solution 2: Configure Service on Both Nodes (Recommended)

**Configuration:**
```sql
-- Make service available on both instances
-- This enables true RAC high availability
ALTER SYSTEM SET service_names='XSTREAMPDB,<other_services>' SCOPE=BOTH SID='<instance1>';
ALTER SYSTEM SET service_names='XSTREAMPDB,<other_services>' SCOPE=BOTH SID='<instance2>';
```

**Backend Pool:**
```
Backend Pool: [Both VIPs]
```

**Pros:**
- ✅ True RAC high availability
- ✅ Automatic failover if one node fails
- ✅ Both VIPs can serve connections
- ✅ No ORA-12514 errors

**Cons:**
- ❓ Requires DBA to configure database service on both nodes
- ❓ Customer may have reasons for single-instance configuration

### Solution 3: Use SCAN Endpoint (If DNS Resolution Available)

**Configuration:**
```
Backend Pool: [SCAN VIP addresses]
```

**Requirement:** DNS resolution for SCAN hostnames from Azure to OCI.

**Pros:**
- ✅ Oracle-native solution
- ✅ SCAN handles service location automatically
- ✅ No ORA-12514 issues

**Cons:**
- ❌ Requires DNS forwarding from Azure to OCI DNS
- ❌ TNS redirect may not work with Confluent Cloud EAP architecture

## Conclusion

**The customer's logic is sound:**

> "If we put both VIPs in the AppGW backend pool, won't AppGW load-balance ~50% of new connections to .40 and get ORA-12514?"

**Answer:** YES - AppGW will load-balance to both VIPs, causing ~50% ORA-12514 errors.

> "Will it perhaps gracefully try the other VIP afterwards?"

**Answer:** NOT RELIABLY - JDBC retry goes back through AppGW with no guarantee of routing to the correct VIP.

**Recommendation for Customer:**

For single-instance database on RAC:
1. **Short-term:** Use only the VIP where the service is registered in AppGW backend pool
2. **Long-term:** Work with DBA to configure service on both nodes for true HA

**AppGW Backend Pool Configuration Rules:**
- **Service on both nodes:** Use both VIPs (full HA)
- **Service on one node only:** Use only that VIP (no HA, but no errors)

## Test Execution Checklist

- [ ] Phase 1: Verify current service registration
- [ ] Phase 2: Simulate single-instance (unregister service from one node)
- [ ] Phase 3: Test both VIPs with service on one node (expect failures)
- [ ] Phase 4: Test single VIP (expect success)
- [ ] Phase 5: Test failover with single VIP (expect no HA)
- [ ] Document results in ORACLE-RAC-HA-TESTING.md
- [ ] Restore service registration to both nodes
- [ ] Restore both VIPs in backend pool

## Risk Assessment

**Risks:**
- Modifying service registration may impact running connector
- Need to restore configuration after testing

**Mitigation:**
- Perform during maintenance window
- Document original configuration before changes
- Have rollback plan ready
