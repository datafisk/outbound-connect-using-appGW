# Azure SQL Failover Pattern - Cost Analysis

This document provides a detailed cost breakdown for the Azure SQL Failover pattern using different connectivity approaches.

> **Scope note:** Figures below cover Azure charges only. Confluent-side Egress Access Point charges depend on cluster type and were not verified; check current Confluent pricing, especially for the dual-EAP option (two EAPs). Option numbers match [docs/FAILOVER-TESTING.md](./docs/FAILOVER-TESTING.md): "Dual EAP" = Option 3, "Application Gateway" = Option 4.

## TL;DR Cost Comparison

| Approach | Monthly Cost | Failover | Manual Intervention |
|----------|--------------|----------|---------------------|
| **Dual EAP** | **~$15** | ✅ Automatic | ❌ None |
| **AppGW + Single EAP** | **~$157-187** | ✅ Automatic | ❌ None |
| **Single EAP** | **~$7** | ⚠️ Manual | ✅ DNS update required |

*Note: Costs exclude Azure SQL Database itself, which is the same across all approaches (~$800-1,600/month for HA setup)*

## Dual Egress Access Points

### Azure Costs

**Private Endpoints** (2 endpoints to regional SQL servers):
- **$0.01/hour per endpoint** × 2 endpoints
- 2 × $0.01 × 730 hours = **~$14.60/month**

**Data Processing**:
- **$0.01 per GB** ingress (pay as you go)
- Typical: 10 GB/month = **$0.10/month**

**Private DNS Zone**:
- **$0.50/month** per zone (privatelink.database.windows.net)

**Total Azure**: **~$15.20/month**

### Confluent Costs

**Egress Access Points**:
- Not verified: check current Confluent pricing for your cluster type
- Do not assume zero; two EAPs also count against cluster quotas

**Total Confluent**: **$0** additional

### Total Monthly Cost: ~$15/month

---

## Application Gateway Approach

### Azure Costs

**Application Gateway (Standard_v2)**:
- **Gateway Hours**: ~$0.20/hour × 730 hours = **~$146/month**
- **Capacity Units** (autoscaling):
  - At 1 unit average: $0.008/hour × 730 = **~$5.84/month**
  - At 2 units average: **~$11.68/month**
- **Data Processing**: $0.008 per GB processed
- **Zone Redundancy**: No additional charge for Standard_v2

**Typical AppGW monthly cost**: **$150-180/month**

**Private Endpoint** (1 endpoint to AppGW):
- **$0.01/hour** × 730 = **~$7.30/month**
- **Data ingress**: $0.01 per GB

**Private DNS Zone**:
- **$0.50/month**

**Total Azure**: **~$157-187/month**

### Confluent Costs

**Egress Access Point**:
- Enterprise cluster: **$0** (included)

**Total Confluent**: **$0** additional

### Total Monthly Cost: ~$157-187/month

---

## Single EAP (Manual Failover)

### Azure Costs

**Private Endpoint** (1 endpoint):
- **$0.01/hour** × 730 = **~$7.30/month**
- **Data ingress**: $0.01 per GB

**Private DNS Zone**:
- **$0.50/month**

**Total Azure**: **~$7.80/month**

### Confluent Costs

**Egress Access Point**:
- Enterprise cluster: **$0** (included)

### Operational Cost

**Manual Intervention**:
- DNS update during failover: ~5-10 minutes
- Connector downtime: ~2-5 minutes
- Depends on failover frequency

### Total Monthly Cost: ~$8/month + operational overhead

---

## Azure SQL Database Costs (All Approaches)

These costs are **identical across all connectivity approaches**:

### Primary Database (GP_S_Gen5_2 - Serverless)

**Compute**:
- **vCore pricing**: $0.5489/vCore/hour (Gen5, 2 vCores)
- **If running 24/7**: 2 × $0.5489 × 730 = **~$801/month**
- **If auto-pause 50%**: **~$400/month**

**Storage**:
- **Active**: Included in compute
- **Paused**: $0.1578/GB/month

### Secondary Database (Geo-Replication)

**Compute**:
- Billed at same rate as primary
- **If running 24/7**: **~$801/month**
- **If auto-pause 50%**: **~$400/month**

**Geo-Replication**:
- **Data transfer**: FREE (Microsoft covers it)

### Total SQL Costs

- **24/7 operation**: **~$1,602/month** (both servers)
- **50% auto-pause**: **~$800/month** (both servers)

---

## Complete Solution Cost Breakdown

### Option 1: Dual EAP + SQL

| Component | Monthly Cost |
|-----------|--------------|
| Azure SQL Primary (24/7) | $801 |
| Azure SQL Secondary (24/7) | $801 |
| Private Endpoints (2×) | $15 |
| Private DNS Zone | $0.50 |
| Data Transfer | ~$5-10 |
| **TOTAL** | **~$1,622/month** |

**With 50% auto-pause**: **~$822/month**

### Option 2: AppGW + Single EAP + SQL

| Component | Monthly Cost |
|-----------|--------------|
| Azure SQL Primary (24/7) | $801 |
| Azure SQL Secondary (24/7) | $801 |
| Application Gateway | $150-180 |
| Private Endpoints | $7 |
| Private DNS Zone | $0.50 |
| Data Transfer | ~$5-10 |
| **TOTAL** | **~$1,764-1,804/month** |

**With 50% auto-pause**: **~$964-1,004/month**

### Option 3: Single EAP + SQL (Manual Failover)

| Component | Monthly Cost |
|-----------|--------------|
| Azure SQL Primary (24/7) | $801 |
| Azure SQL Secondary (24/7) | $801 |
| Private Endpoint (1×) | $7 |
| Private DNS Zone | $0.50 |
| Data Transfer | ~$5-10 |
| **TOTAL** | **~$1,614/month** |

**With 50% auto-pause**: **~$814/month**

---

## Cost Optimization Strategies

### 1. SQL Serverless Auto-Pause

Configure SQL databases to auto-pause after 60 minutes of inactivity:

```bash
az sql db update \
  --name peter-test-db \
  --server pg-uswest2 \
  --resource-group petergustafss-test \
  --auto-pause-delay 60
```

**Savings**: Up to 50% on SQL compute costs (~$800/month)

### 2. Lower SQL Tier

If workload permits, use 1 vCore instead of 2:

```bash
az sql db update \
  --name peter-test-db \
  --server pg-uswest2 \
  --resource-group petergustafss-test \
  --capacity 1
```

**Savings**: ~$400/month per server

### 3. Reuse Existing Application Gateway

If you already have an AppGW for other purposes, adding SQL backends costs **$0** incremental AppGW cost (only ~$7 for Private Endpoint).

### 4. Right-Size AppGW Autoscaling

Adjust min/max capacity units based on actual load:

```hcl
autoscale_configuration {
  min_capacity = 0  # Scale to zero when idle
  max_capacity = 5  # Lower max if not needed
}
```

**Savings**: ~$5-20/month depending on usage

---

## Cost Comparison Summary

### Cheapest Option
**Single EAP with Manual Failover**: ~$814-1,614/month
- Requires operational overhead during failover
- Not recommended for production

### Best Value
**Dual EAP**: ~$822-1,622/month
- Only ~$8/month more than manual approach
- Fully automatic failover
- Zero operational overhead
- Production-ready

### Premium Option
**Application Gateway**: ~$964-1,804/month
- ~$142-182/month more than Dual EAP
- Driver-agnostic (works with any connector)
- Advanced routing capabilities
- Best if reusing existing AppGW

---

## ROI Analysis

### Dual EAP vs Manual Failover

**Cost difference**: ~$8/month = ~$96/year

**Value delivered**:
- Zero downtime during failover
- No manual intervention required
- No on-call engineer time needed
- Reduced risk of human error

**Break-even**: If failover happens more than once per year, Dual EAP pays for itself in saved engineering time.

### AppGW vs Dual EAP

**Cost difference**: ~$142-182/month = ~$1,704-2,184/year

**Additional value**:
- Driver-agnostic solution
- Can support multiple connectors/backends
- Advanced health probing
- Layer 7 routing capabilities

**When to choose AppGW**:
- Already using AppGW for other services (incremental cost ~$7/month)
- Need driver-agnostic solution
- Require advanced routing features
- Multiple connectors to same SQL failover group

---

## Azure Reserved Instances

Consider Azure Reserved Instances for SQL Database to save 30-40% on compute:

**1-Year RI**: ~30% savings = ~$240/month saved
**3-Year RI**: ~40% savings = ~$320/month saved

Not applicable to Private Endpoints or AppGW (already committed resources).

---

## Additional Considerations

### Data Transfer Costs

**Within Region** (Free):
- AppGW ↔ Private Endpoint in same region
- Connector ↔ EAP in same region

**Cross-Region**:
- SQL Geo-Replication: **FREE** (Microsoft covers)
- Confluent ↔ Azure Private Link: Minimal (covered by EAP)

**Outbound to Internet**:
- First 100 GB/month: **FREE**
- Beyond: $0.087/GB
- Not applicable for private connectivity

### Scaling Costs

As data volume increases:

**Dual EAP**:
- Linear scaling: $0.01/GB data ingress
- No infrastructure scaling needed

**AppGW**:
- Automatic capacity unit scaling
- $0.008/hour per additional capacity unit
- $0.008/GB data processing

---

## Choosing

Cost is one input. Dual EAP (Option 3) is cheapest on the Azure side but depends on public DNS and uses two EAPs. AppGW (Option 4) costs ~$150-180/month but is fully private and the EAP/AppGW can be shared across connectors, so it amortizes well when several SQL setups or connectors are in scope. See [docs/FAILOVER-TESTING.md](./docs/FAILOVER-TESTING.md) for the full option comparison.
