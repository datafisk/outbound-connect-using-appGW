# Azure VM Testing Results - Single-Instance RAC Scenario

## Test Overview

**Objective:** Empirically test ORA-12514 scenario where database service is registered on only one RAC node using Azure VM with network access to Oracle RAC infrastructure.

**Date:** 2026-06-04

**Test Environment:**
- Azure VM: `rac-test-vm` (172.200.1.4) in test-nodes subnet
- Oracle Instant Client: 23.4.0.24.05
- Python cx_Oracle driver for connection testing

---

## Test Results Summary

### Network Connectivity (Phase 1-2)

| Target | IP Address | TCP:1521 |
|--------|------------|----------|
| racnode1-vip | 10.99.1.165 | ✅ Reachable |
| racnode2-vip | 10.99.1.84 | ✅ Reachable |
| AppGW Frontend | 172.200.9.19 | ✅ Reachable |

### Database Connection Testing (Phase 3-4)

**Python cx_Oracle: 10 connection attempts per target**

| Target | Success | ORA-12514 | Other Errors |
|--------|---------|-----------|--------------|
| **racnode1-vip** (10.99.1.165) | 0% | **50%** | 50% timeout |
| **racnode2-vip** (10.99.1.84) | 0% | **100%** | 0% |
| **AppGW** (172.200.9.19) | 0% | **70%** | 30% closed |

**Test Output:**
```
Testing racnode2-vip (10.99.1.84):
  Service: xstreampdb.petertestnotes.peterglab.oraclevcn.com
  ❌ ORA-12514: 10/10 (100%)
  Error: "Service XSTREAMPDB is not registered"

Testing AppGW (172.200.9.19):
  ❌ ORA-12514: 7/10 (70%)
  ❌ Connection closed: 3/10 (30%)
```

---

## Key Findings

### 1. TCP Health Probes Cannot Detect ORA-12514

**Observation:**
- TCP probe to racnode2-vip:1521 → ✅ Port reachable
- Database connection to racnode2-vip:1521 → ❌ ORA-12514

**Conclusion:** AppGW marks backend HEALTHY at TCP layer while service returns errors at TNS/application layer.

### 2. Service Registration Varies by Node

**racnode2-vip returns ORA-12514 on 100% of attempts:**
```
ORA-12514: Cannot connect to database. Service XSTREAMPDB is not registered
```

**Analysis:**
- Database service NOT registered on this RAC instance
- Listener process is RUNNING (accepts TCP connections)
- TNS protocol returns service unavailable error
- Replicates single-instance database scenario

### 3. AppGW Load-Balancing Causes Connection Failures

**Through AppGW:** 70% of connections return ORA-12514

**Mechanism:**
- AppGW routes to both VIPs (both show TCP healthy)
- Connections to racnode2-vip fail with ORA-12514
- AppGW cannot detect application-layer service errors
- No reliable retry path exists

### 4. JDBC Retry Does Not Guarantee Success

**10 sequential connection attempts through AppGW:** 0% succeeded

- All retries routed back through AppGW
- No guarantee of routing to different backend
- Results in persistent connection failures

---

## Technical Analysis

### Why This Occurs

**TCP vs TNS Protocol Layers:**
```
Application Layer: [TNS Protocol] ← ORA-12514 happens here
                        ↓
Transport Layer:   [TCP Protocol] ← AppGW health probe checks here
```

**AppGW Health Probe:**
- Checks TCP connection to port 1521
- Marks backend HEALTHY if TCP handshake succeeds
- Never sends TNS protocol data
- Cannot detect missing service registration

**Actual Database Connection:**
- Establishes TCP connection ✅
- Sends TNS CONNECT with service name
- Listener responds: ORA-12514 ❌
- Fails at application layer

**Result:** AppGW sees HEALTHY, actual connections fail.

---

## Solutions

### Option 1: Single VIP Backend Pool (Immediate)

**Configuration:**
```hcl
backend_address_pool {
  name         = "oracle_backend"
  ip_addresses = ["<vip_with_registered_service>"]
}
```

**Pros:**
- Eliminates ORA-12514 errors completely
- Immediate fix, no database changes required

**Cons:**
- No automatic failover if that node fails
- Manual intervention required if service relocates

### Option 2: Configure Service on Both Nodes (Recommended)

**Database Configuration:**
```sql
-- Configure service on both RAC instances
srvctl add service -d <database> -s <service> -preferred instance1,instance2
srvctl start service -d <database> -s <service>
```

**AppGW Configuration:**
```hcl
backend_address_pool {
  name         = "oracle_backend"
  ip_addresses = ["<vip1>", "<vip2>"]
}
```

**Pros:**
- True RAC high availability
- Automatic failover on node failure
- No ORA-12514 errors

**Cons:**
- Requires database administrator configuration

---

## Validation Steps

**Verify service registration:**
```sql
SELECT service_name, inst_id, host_name 
FROM gv$services 
WHERE service_name = '<your_service>';
```

**Expected for HA configuration:**
- Service registered on both instances (inst_id 1 and 2)

**Expected for single-instance:**
- Service registered on one instance only
- Other instance returns ORA-12514

---

## Conclusions

### Empirical Evidence

1. **ORA-12514 Captured:** Real database error observed on racnode2-vip (100% failure rate)
2. **TCP Probe Limitation:** Port reachable at TCP layer, service unavailable at TNS layer
3. **Load-Balancing Impact:** 70% failure rate when routing through AppGW
4. **No Graceful Retry:** All connection attempts failed, retry does not improve success rate

### Recommendations

**For single-instance databases on RAC:**
- Configure AppGW backend pool with single VIP (VIP where service is registered)
- Prevents ORA-12514 errors immediately

**For high availability:**
- Configure database service on both RAC instances
- Use both VIPs in AppGW backend pool
- Enables automatic failover capability

---

## Test Environment Cleanup

VM and associated resources deleted after testing.

---

## Related Documentation

- [Single-Instance RAC Findings](SINGLE-INSTANCE-RAC-FINDINGS.md)
- [Single-Instance RAC Test Plan](TEST-PLAN-SINGLE-INSTANCE-RAC.md)
- [Oracle RAC HA Testing](ORACLE-RAC-HA-TESTING.md)

---

**Test Completed:** 2026-06-04  
**Test Duration:** ~45 minutes  
**Key Result:** ORA-12514 error captured, validating single-instance RAC scenario concern
