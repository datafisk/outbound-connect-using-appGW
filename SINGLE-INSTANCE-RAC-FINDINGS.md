# Single-Instance Database on 2-Node RAC Cluster - Test Findings

## Customer Scenario

**Configuration:**
- 2-node Oracle RAC cluster  
- Single-instance database (service registered on only ONE node)
- Node 1 listener: Returns ORA-12514 (service not registered)
- Node 2 listener: Service registered, connections succeed
- SCAN DNS: Currently redirects all clients to Node 2

**Customer Question:**
> "If we put both VIPs in the AppGW backend pool, won't AppGW load-balance ~50% of new connections to Node 1 and get ORA-12514? Will it perhaps gracefully try the other VIP afterwards?"

---

## Test Results Summary

### Test 1: VIP Failover (Standard RAC Configuration)

**Configuration:**
- Both VIPs in backend pool
- Database service registered on BOTH nodes (standard RAC)

**Procedure:**
1. Stopped racnode2 (simulating node failure)
2. Monitored connector for 5+ minutes
3. Restarted racnode2

**Results:**
- ✅ **Zero downtime** - VIP automatically relocated to surviving node
- ✅ **Seamless failover** - Connector remained RUNNING throughout
- ✅ **Automatic recovery** - Node restart transparent to application

**Conclusion:** When service is registered on both nodes, VIP failover provides perfect HA.

### Test 2: Database Startup Window

**Configuration:**
- Both VIPs in backend pool
- Monitored during racnode2 restart

**Objective:** Catch the brief window when listener is up but database instance hasn't registered services yet.

**Results:**
- ✅ Connector remained RUNNING throughout
- ⚠️  ORA-12514 window too brief to catch with 10-second polling
- ✅ Database instance auto-starts and registers services within 1-2 minutes

**Conclusion:** In properly configured RAC, startup ORA-12514 window is transient and doesn't cause persistent issues.

---

## Analysis: Customer Scenario Validation

### Why Customer's Concern is Valid

**AppGW Health Probe Limitation:**

```
Health Probe Type: TCP
Check: Can port 1521 accept connections?
Node 1 Listener: ✅ RUNNING → Health Probe PASSES
Node 2 Listener: ✅ RUNNING → Health Probe PASSES

But actual application-layer behavior:
Node 1 Connection Attempt: ORA-12514 (service not registered)
Node 2 Connection Attempt: SUCCESS
```

**Critical Issue:** TCP health probes cannot detect ORA-12514 errors. This is an application-layer TNS protocol error, not a TCP-layer failure.

### Load Balancing Behavior

With both VIPs in the backend pool:

1. AppGW marks both VIPs as **HEALTHY** (TCP probe succeeds)
2. AppGW load-balances connections: ~50% to each VIP
3. Connections to Node 1 VIP: **ORA-12514** (service unknown)
4. Connections to Node 2 VIP: **SUCCESS**

**Result:** ~50% of connection attempts fail intermittently.

### Retry Behavior - Will It Gracefully Recover?

**Short Answer: NO**

When connector gets ORA-12514:
1. Oracle JDBC driver classifies it as `SQLRecoverableException`
2. Connector retry logic activates
3. **Retry goes back through AppGW**
4. AppGW may route retry to Node 1 again → another ORA-12514
5. No guarantee of eventual success

**Stack Trace During Failure:**
```
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

**Impact:**
- ❌ Unpredictable connection success rate
- ❌ Intermittent connector failures
- ❌ Potential connector startup failures
- ❌ Degraded reliability

---

## Solutions and Recommendations

### Solution 1: Single VIP in Backend Pool (Immediate Fix)

**Configuration:**
```hcl
backend_address_pool {
  name         = "oracle_rac_pool"
  ip_addresses = ["<node2_vip>"]  # Only the VIP where service is registered
}
```

**Pros:**
- ✅ Eliminates ORA-12514 errors completely
- ✅ Predictable connection behavior
- ✅ Reliable connector operation
- ✅ No code or DBA changes required

**Cons:**
- ❌ No automatic failover if Node 2 fails
- ❌ Manual intervention required if service relocates
- ❌ Defeats RAC high availability purpose
- ❌ Single point of failure

**Use Case:** Short-term workaround for single-instance databases on RAC clusters.

### Solution 2: Configure Service on Both Nodes (Recommended)

**Configuration:**
```sql
-- DBA configures database service on both RAC instances
-- Example for service 'MYSERVICE':

-- On each node, add service to initialization parameters
ALTER SYSTEM SET service_names='MYSERVICE,<other_services>' SCOPE=BOTH SID='instance1';
ALTER SYSTEM SET service_names='MYSERVICE,<other_services>' SCOPE=BOTH SID='instance2';

-- OR create service via SRVCTL (preferred method):
srvctl add service -d <database_name> -s MYSERVICE -preferred instance1,instance2
srvctl start service -d <database_name> -s MYSERVICE
```

**AppGW Configuration:**
```hcl
backend_address_pool {
  name         = "oracle_rac_pool"
  ip_addresses = ["<node1_vip>", "<node2_vip>"]  # Both VIPs
}
```

**Pros:**
- ✅ True RAC high availability
- ✅ Automatic failover if one node fails
- ✅ Both VIPs can serve connections
- ✅ No ORA-12514 errors
- ✅ Balanced load across nodes
- ✅ Production-grade solution

**Cons:**
- 🔧 Requires DBA to reconfigure database
- 🔧 May require application/architecture review

**Use Case:** Long-term production solution for mission-critical systems.

### Solution 3: Use SCAN Endpoint (If DNS Available)

**Configuration:**
```hcl
backend_address_pool {
  name         = "oracle_rac_pool"
  fqdns        = ["<scan-hostname>"]  # e.g., racdb-scan.example.com
}
```

**Requirements:**
- DNS resolution from Azure to Oracle DNS
- Azure Private DNS zones or DNS forwarding configured

**Pros:**
- ✅ Oracle-native solution
- ✅ SCAN handles service location automatically
- ✅ No ORA-12514 issues
- ✅ Automatic adaptation to service changes

**Cons:**
- ❌ Requires DNS infrastructure setup
- ❌ TNS redirect may not work with Confluent Cloud EAP architecture
- ❌ Additional network configuration complexity

**Use Case:** Environments with established cross-cloud DNS infrastructure.

---

## Configuration Decision Matrix

| Scenario | Backend Pool Configuration | HA Capability | ORA-12514 Risk |
|----------|---------------------------|---------------|----------------|
| **Standard RAC (service on all nodes)** | Both VIPs | ✅ Full HA | ❌ None |
| **Single-instance (service on one node)** | Single VIP only | ❌ No HA | ❌ None |
| **Single-instance with both VIPs** | Both VIPs | ⚠️  Partial | 🔴 **~50% failures** |
| **SCAN with DNS** | SCAN FQDN | ✅ Full HA | ❌ None |

---

## Customer Answer

**Question:** "If we put both VIPs in the AppGW backend pool, won't AppGW load-balance ~50% of new connections and get ORA-12514?"

**Answer:** ✅ **YES - Customer's concern is 100% correct.**

AppGW will:
1. Mark both VIPs as HEALTHY (TCP health probe cannot detect ORA-12514)
2. Load-balance ~50% of connections to each VIP
3. Route ~50% of connections to the VIP without the registered service
4. Those connections will fail with ORA-12514

**Question:** "Will it perhaps gracefully try the other VIP afterwards?"

**Answer:** ❌ **NO - Retry is NOT reliable.**

Oracle JDBC driver retry logic:
- Retries go back through AppGW
- AppGW may route retry to the same failing VIP again
- No guarantee of successful connection
- Results in unpredictable intermittent failures

---

## Recommended Action Plan

### Immediate (Temporary Fix)

1. **Configure AppGW backend pool with single VIP**
   - Use only the VIP where database service is registered
   - Eliminates ORA-12514 errors
   - Connector will operate reliably

2. **Document the limitation**
   - No automatic failover capability
   - Manual intervention required if service relocates

### Long-term (Production Solution)

1. **Work with DBA to configure service on both nodes**
   - Enables true RAC high availability
   - Both VIPs can serve connections
   - Automatic failover capability

2. **Update AppGW backend pool to include both VIPs**
   - After service is configured on both nodes
   - Test failover behavior
   - Validate zero downtime during node failures

### Validation Steps

After implementing long-term solution:

```bash
# Test service registration on both nodes
# SSH to each RAC node and run:
lsnrctl services | grep -i <service_name>

# Should show service registered on both nodes

# Verify AppGW backend pool
az network application-gateway address-pool show \
  -g <resource-group> \
  --gateway-name <appgw-name> \
  -n <backend-pool-name>

# Should show both VIP IPs

# Test connector behavior
confluent connect cluster describe <connector-id> --environment <env-id>

# Should show STATUS: RUNNING
```

---

## Technical Deep-Dive: Why TCP Probes Can't Detect ORA-12514

### TCP vs TNS Protocol Layers

```
Application Layer:  [TNS Protocol - Service Registration]
                           ↑
                    ORA-12514 happens here
                           ↓
Transport Layer:    [TCP Protocol - Port 1521]
                           ↑
                    AppGW health probe checks here
```

**AppGW Health Probe:**
1. Initiates TCP connection to port 1521
2. Checks if TCP handshake succeeds
3. Marks backend HEALTHY if TCP accepts connection
4. Closes connection without sending TNS protocol data

**Actual Connection Attempt:**
1. Initiates TCP connection to port 1521 ✅
2. Sends TNS CONNECT packet with service name
3. Listener responds: "ORA-12514 - Service unknown" ❌
4. Connection fails at application layer

**Result:** AppGW sees HEALTHY, but actual connections fail.

### Why Oracle Listener Accepts TCP But Returns ORA-12514

Oracle listener architecture:
1. Listener process runs on each RAC node
2. Listens on port 1521 (TCP)
3. Maintains registry of available database services
4. When connection request arrives:
   - Accepts TCP connection ✅
   - Parses TNS CONNECT packet
   - Checks if requested service is registered
   - If NOT registered: Returns ORA-12514 ❌
   - If registered: Redirects to database instance ✅

**This means:**
- Listener is "up" (TCP port open) ≠ Service is available
- TCP health probe CANNOT detect missing service registration
- Only application-layer TNS protocol can detect ORA-12514

---

## Conclusion

The customer's analysis is **technically accurate** and their concern is **valid**.

**For single-instance databases on RAC clusters:**

✅ **DO:** Configure AppGW backend pool with only the VIP where service is registered

❌ **DON'T:** Include both VIPs when service is only on one node

**For production systems requiring HA:**

✅ **DO:** Configure database service on both RAC nodes

✅ **DO:** Use both VIPs in AppGW backend pool

✅ **DO:** Test failover behavior thoroughly

---

## Related Documentation

- [Oracle RAC HA Testing](ORACLE-RAC-HA-TESTING.md)
- [Oracle RAC Quick Start](ORACLE-RAC-QUICKSTART.md)
- [Oracle RAC AppGW Setup](ORACLE-RAC-APPGW-SETUP.md)
- [Test Plan](TEST-PLAN-SINGLE-INSTANCE-RAC.md)
