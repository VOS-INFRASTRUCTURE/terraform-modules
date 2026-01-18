# AWS ElastiCache - Complete Guide

## Table of Contents
1. [What is ElastiCache?](#what-is-elasticache)
2. [ElastiCache vs Self-Managed Redis on EC2](#elasticache-vs-self-managed-redis-on-ec2)
3. [ElastiCache Engines: Redis OSS vs Valkey](#elasticache-engines-redis-oss-vs-valkey)
4. [Single Node vs Multi-Node (HA)](#single-node-vs-multi-node-ha)
5. [Cluster Modes](#cluster-modes)
6. [Cost Breakdown](#cost-breakdown)
7. [When to Use What](#when-to-use-what)
8. [Architecture Diagrams](#architecture-diagrams)
9. [Migration Path](#migration-path)

---

## What is ElastiCache?

**AWS ElastiCache** is a fully managed in-memory caching service that supports two engines:
- **Redis OSS** (Open Source Software)
- **Valkey** (AWS's Redis-compatible fork - cheaper!)

### Key Benefits Over Self-Managed Redis

| Feature | ElastiCache | EC2 + Redis |
|---------|-------------|-------------|
| **Setup Time** | 5 minutes | 1-2 hours |
| **Patching** | Automatic | Manual |
| **Backups** | Automatic | Manual scripts |
| **Monitoring** | Built-in CloudWatch | Manual setup |
| **High Availability** | 1-click setup | Complex configuration |
| **Scaling** | 1-click resize | Downtime required |
| **Security** | VPC, encryption, IAM | Manual hardening |
| **Maintenance** | AWS handles it | You handle it |

### What ElastiCache Does for You

```
┌────────────────────────────────────────────────────────────┐
│                    AWS ElastiCache                          │
│                                                             │
│  ✅ Automatic failover (HA mode)                           │
│  ✅ Automatic backups (snapshots)                          │
│  ✅ Automatic patching/updates                             │
│  ✅ Monitoring & metrics (CloudWatch)                      │
│  ✅ Encryption at rest & in transit                        │
│  ✅ VPC security & network isolation                       │
│  ✅ Multi-AZ deployment                                    │
│  ✅ Read replicas for scaling                              │
│  ✅ Parameter groups for tuning                            │
│                                                             │
│  ❌ You DON'T manage: OS, Redis installation, patches,     │
│     backups, failover, monitoring setup                    │
└────────────────────────────────────────────────────────────┘
```

---

## ElastiCache vs Self-Managed Redis on EC2

### Cost Comparison

**For 1 GB memory:**

| Setup | Monthly Cost | Your Effort | Reliability |
|-------|--------------|-------------|-------------|
| **EC2 t4g.micro + Redis** | $7-8 | ❌ High (install, patch, monitor, backup) | ⚠️ No HA |
| **ElastiCache Valkey t4g.micro (1 node)** | $14-18 | ✅ Very Low (click & forget) | ⚠️ No HA |
| **ElastiCache Valkey t4g.micro (2 nodes HA)** | $26-36 | ✅ Very Low | ✅ Auto-failover |

### Effort Breakdown

**EC2 + Redis (Self-Managed):**
```
Initial Setup:
  ✅ Launch EC2 instance
  ✅ Install Redis
  ✅ Configure security groups
  ✅ Set up monitoring
  ✅ Configure backups
  ✅ Harden security
  ─────────────────────
  Time: 1-2 hours

Ongoing Maintenance (Monthly):
  ✅ Apply security patches
  ✅ Update Redis version
  ✅ Monitor disk space
  ✅ Verify backups
  ✅ Handle failures manually
  ─────────────────────
  Time: 2-4 hours/month
```

**ElastiCache:**
```
Initial Setup:
  ✅ Click "Create cluster"
  ✅ Select instance type
  ✅ Configure VPC/subnets
  ─────────────────────
  Time: 5-10 minutes

Ongoing Maintenance (Monthly):
  ✅ Nothing - AWS handles everything
  ─────────────────────
  Time: 0 hours/month
```

### When to Choose EC2 + Redis

✅ **Choose EC2 + Redis if:**
- Extremely tight budget ($7/month vs $14/month matters)
- You have DevOps expertise
- You're OK with manual maintenance
- Development/testing environment
- You need specific Redis versions/modules not available in ElastiCache

### When to Choose ElastiCache

✅ **Choose ElastiCache if:**
- You value your time (ops effort vs cost)
- Production environment
- You need high availability
- You want automatic backups
- Your team lacks Redis expertise
- Compliance requires managed services

---

## ElastiCache Engines: Redis OSS vs Valkey

### What is Valkey?

**Valkey** is AWS's fork of Redis, created after Redis changed its license in 2024. It's **fully compatible** with Redis but **20-30% cheaper** on ElastiCache.

### Comparison

| Feature | Redis OSS | Valkey |
|---------|-----------|--------|
| **Protocol** | Redis | Redis (100% compatible) |
| **Performance** | Excellent | Excellent (same) |
| **Compatibility** | Redis 7.x | Redis 7.x compatible |
| **Price (t4g.micro)** | $20-25/month | $14-18/month |
| **Savings** | - | **30% cheaper** ✅ |
| **AWS Support** | Standard | Priority (AWS's own) |
| **Future Updates** | Slower | Faster (AWS-managed) |

### Which Should You Use?

```
┌─────────────────────────────────────────────────────────┐
│  Use Valkey (Recommended for 95% of use cases)         │
│                                                         │
│  ✅ Same Redis protocol (drop-in replacement)          │
│  ✅ 30% cheaper than Redis OSS                         │
│  ✅ Better AWS integration                             │
│  ✅ Actively developed by AWS                          │
│  ✅ All your Redis code works unchanged                │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  Use Redis OSS only if:                                 │
│                                                         │
│  • Specific Redis modules needed (RedisJSON, etc.)     │
│  • Company policy requires "official Redis"            │
│  • Specific Redis version compatibility needed         │
└─────────────────────────────────────────────────────────┘
```

**Our Recommendation: Use Valkey** - Save 30%, same performance!

---

## Single Node vs Multi-Node (HA)

### Single Node (No High Availability)

**What is it?**
One Redis/Valkey server handling all requests.

```
┌─────────────────────────────────────────────────────────┐
│                    Single Node                          │
│                                                         │
│         ┌────────────────────────┐                     │
│         │                        │                     │
│         │   ElastiCache Node     │                     │
│         │   (Primary)            │                     │
│         │                        │                     │
│         │   Read + Write         │                     │
│         │   1.37 GB RAM          │                     │
│         │                        │                     │
│         └────────────────────────┘                     │
│                  ▲                                      │
│                  │                                      │
│                  │ All traffic                          │
│                  │                                      │
│         ┌────────┴────────┐                            │
│         │  Application    │                            │
│         └─────────────────┘                            │
│                                                         │
│  ❌ If node fails → Cache is DOWN                      │
│  ⏱️ Manual recovery required                           │
│  💰 Cost: $14-18/month (Valkey t4g.micro)              │
└─────────────────────────────────────────────────────────┘
```

**Pros:**
- ✅ Cheaper ($14-18/month vs $26-36/month)
- ✅ Simpler setup
- ✅ Good for dev/staging

**Cons:**
- ❌ No automatic failover
- ❌ Downtime if node fails
- ❌ Not recommended for production

### Multi-Node with High Availability (HA)

**What is it?**
Multiple Redis/Valkey servers with automatic failover.

```
┌─────────────────────────────────────────────────────────┐
│              Multi-Node (High Availability)             │
│                                                         │
│  ┌────────────────────┐         ┌────────────────────┐ │
│  │  Primary Node      │────────→│  Replica Node      │ │
│  │  (AZ-1)            │         │  (AZ-2)            │ │
│  │                    │ Sync    │                    │ │
│  │  Read + Write      │─────────│  Read-only         │ │
│  │  1.37 GB RAM       │         │  1.37 GB RAM       │ │
│  └────────────────────┘         └────────────────────┘ │
│           ▲                              ▲             │
│           │ Writes                       │ Reads       │
│           │                              │             │
│      ┌────┴──────────────────────────────┴────┐       │
│      │        Application (Load Balanced)     │       │
│      └────────────────────────────────────────┘       │
│                                                         │
│  If Primary Fails:                                     │
│  ┌─────────────────────────────────────────┐          │
│  │ 1. Replica detects failure (15-30s)     │          │
│  │ 2. Replica promoted to Primary (30-60s) │          │
│  │ 3. New replica created automatically    │          │
│  │ 4. Application reconnects automatically │          │
│  └─────────────────────────────────────────┘          │
│                                                         │
│  ✅ Automatic failover in 30-60 seconds               │
│  ✅ Zero data loss (with proper sync)                 │
│  💰 Cost: $26-36/month (Valkey t4g.micro × 2)         │
└─────────────────────────────────────────────────────────┘
```

**Pros:**
- ✅ Automatic failover (30-60 seconds)
- ✅ No manual intervention needed
- ✅ Multi-AZ (survives AZ failure)
- ✅ Read scaling (replicas handle reads)
- ✅ Production-ready

**Cons:**
- ❌ 2× cost ($26-36/month vs $14-18/month)
- ❌ Slightly more complex

### Failover Process (Automatic)

```
Normal Operation:
┌─────────┐     Replication    ┌─────────┐
│ Primary │ ─────────────────→ │ Replica │
│ (Write) │                    │ (Read)  │
└─────────┘                    └─────────┘
     ▲                              ▲
     │                              │
     └──────── App ─────────────────┘

Primary Fails:
┌─────────┐                    ┌─────────┐
│ Primary │ ❌ FAILED           │ Replica │
│  (X)    │                    │ Detected│
└─────────┘                    └─────────┘
                                    │
                                    ↓
                            Promotes itself

After Failover (30-60 seconds):
                               ┌─────────┐
                               │ Primary │ (Was replica)
                               │ (Write) │
                               └─────────┘
                                    ▲
                                    │
                                App reconnects
                                    │
                               ┌─────────┐
                               │New Repli│ (Created auto)
                               │  (Read) │
                               └─────────┘
```

---

## Cluster Modes

### Cluster Mode Disabled (Default - Recommended)

**What is it?**
All data on one primary node (+ replicas for HA).

**Capacity:** Limited by single node size (up to 317 GB with r7g.4xlarge)

```
┌──────────────────────────────────────────────┐
│  Cluster Mode: Disabled (Simple)            │
│                                              │
│  ┌────────────┐         ┌────────────┐      │
│  │  Primary   │────────→│  Replica   │      │
│  │  All Data  │         │  All Data  │      │
│  │  1 GB      │         │  1 GB      │      │
│  └────────────┘         └────────────┘      │
│                                              │
│  ✅ Simple to use                           │
│  ✅ Good for < 10 GB                        │
│  ✅ Supports most use cases                 │
└──────────────────────────────────────────────┘
```

**Use this for: 99% of use cases**

### Cluster Mode Enabled (Advanced)

**What is it?**
Data sharded (split) across multiple nodes.

**Capacity:** Scales horizontally (up to 500 nodes × 317 GB = 158 TB)

```
┌──────────────────────────────────────────────┐
│  Cluster Mode: Enabled (Sharded)            │
│                                              │
│  ┌────────┐  ┌────────┐  ┌────────┐         │
│  │ Shard1 │  │ Shard2 │  │ Shard3 │         │
│  │ 33% of │  │ 33% of │  │ 33% of │         │
│  │  data  │  │  data  │  │  data  │         │
│  └────────┘  └────────┘  └────────┘         │
│      │            │            │             │
│      ↓            ↓            ↓             │
│  ┌────────┐  ┌────────┐  ┌────────┐         │
│  │Replica1│  │Replica2│  │Replica3│         │
│  └────────┘  └────────┘  └────────┘         │
│                                              │
│  ✅ Scales to 100+ GB                       │
│  ⚠️ More complex                            │
│  ⚠️ Some Redis commands don't work          │
└──────────────────────────────────────────────┘
```

**Use this for: > 10 GB data or need > 500k ops/sec**

### Which Cluster Mode?

```
┌─────────────────────────────────────────────────────┐
│  Your Data Size              Recommendation         │
├─────────────────────────────────────────────────────┤
│  < 1 GB                       Cluster Mode Disabled │
│  1 GB - 10 GB                 Cluster Mode Disabled │
│  10 GB - 100 GB               Consider Enabled      │
│  > 100 GB                     Cluster Mode Enabled  │
└─────────────────────────────────────────────────────┘
```

**For most applications: Use Cluster Mode Disabled**

---

## Cost Breakdown

### ElastiCache Valkey Pricing (Recommended)

**t4g.micro (1.37 GB RAM):**
- **Single Node:** $14-18/month
- **2 Nodes (HA):** $26-36/month

**t4g.small (2.78 GB RAM):**
- **Single Node:** $28-36/month
- **2 Nodes (HA):** $52-72/month

**t4g.medium (5.56 GB RAM):**
- **Single Node:** $56-72/month
- **2 Nodes (HA):** $104-144/month

### ElastiCache Redis OSS Pricing (More Expensive)

**t4g.micro (1.37 GB RAM):**
- **Single Node:** $20-25/month
- **2 Nodes (HA):** $40-50/month

**Price Difference: Redis OSS is 30-40% more expensive than Valkey!**

### Complete Cost Example

**Scenario: Production app with 1 GB cache**

| Item | Single Node | HA (2 Nodes) |
|------|-------------|--------------|
| ElastiCache Valkey t4g.micro | $15/month | $30/month |
| Data transfer (out) | $1-2/month | $1-2/month |
| Backup storage (optional) | $0.50/month | $0.50/month |
| **Total** | **~$16-18/month** | **~$31-33/month** |

**Compare to EC2 + Redis:**
| Item | Cost |
|------|------|
| EC2 t4g.micro | $7/month |
| EBS storage | $0.80/month |
| Your time (2-4 hrs/month @ $50/hr) | $100-200/month |
| **Total** | **~$107-208/month** |

**Conclusion: ElastiCache saves you money when you factor in your time!**

---

## When to Use What

### Decision Tree

```
Start: Do you need Redis/Valkey?
│
├─ < 100 MB cache, dev/test only
│  └─→ EC2 t4g.nano + Redis ($4-5/month) ✅
│
├─ ~1 GB cache, tight budget, have DevOps skills
│  └─→ EC2 t4g.micro + Redis ($7-8/month) ✅
│
├─ ~1 GB cache, production, need simplicity
│  ├─ Non-critical app (can tolerate 5-10 min downtime)
│  │  └─→ ElastiCache Valkey t4g.micro - 1 node ($15/month) ✅
│  │
│  └─ Critical app (need < 1 min recovery)
│     └─→ ElastiCache Valkey t4g.micro - 2 nodes HA ($30/month) ✅
│
├─ 2-5 GB cache, production
│  └─→ ElastiCache Valkey t4g.small - 2 nodes HA ($60/month) ✅
│
└─ > 10 GB cache, high traffic
   └─→ ElastiCache Valkey Cluster Mode Enabled ($100+/month) ✅
```

### By Use Case

| Use Case | Recommendation | Monthly Cost |
|----------|----------------|--------------|
| **Local development** | Docker Redis on laptop | $0 |
| **Staging/Test** | EC2 t4g.nano + Redis | $4-5 |
| **Small production (non-critical)** | ElastiCache Valkey t4g.micro (1 node) | $15 |
| **Production (standard)** | ElastiCache Valkey t4g.micro (2 nodes HA) | $30 |
| **Production (critical)** | ElastiCache Valkey t4g.small (2 nodes HA) | $60 |
| **High-scale production** | ElastiCache Valkey r7g.large (cluster) | $200+ |

---

## Architecture Diagrams

### Single Node Architecture

```
┌──────────────────────────────────────────────────────────┐
│                         VPC                              │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │              Application Subnet (AZ-1)             │ │
│  │                                                    │ │
│  │  ┌──────────────┐      ┌──────────────┐          │ │
│  │  │   EC2/ECS    │      │   EC2/ECS    │          │ │
│  │  │  App Server  │      │  App Server  │          │ │
│  │  └──────┬───────┘      └──────┬───────┘          │ │
│  │         │                     │                   │ │
│  │         └──────────┬──────────┘                   │ │
│  │                    │                              │ │
│  └────────────────────┼──────────────────────────────┘ │
│                       │                                 │
│  ┌────────────────────┼──────────────────────────────┐ │
│  │         ElastiCache Subnet (AZ-1)                │ │
│  │                    │                              │ │
│  │         ┌──────────▼──────────┐                  │ │
│  │         │  ElastiCache Node   │                  │ │
│  │         │  (Valkey t4g.micro) │                  │ │
│  │         │  1.37 GB RAM        │                  │ │
│  │         │  Read + Write       │                  │ │
│  │         └─────────────────────┘                  │ │
│  │                                                   │ │
│  └───────────────────────────────────────────────────┘ │
│                                                          │
│  Security Group: Only app subnet can access ElastiCache │
└──────────────────────────────────────────────────────────┘

Cost: $15/month
HA: No (if node fails, cache is down)
```

### Multi-Node HA Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                            VPC                                   │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                  Application Subnets                      │  │
│  │                                                           │  │
│  │  ┌─────────────────┐            ┌─────────────────┐     │  │
│  │  │   AZ-1 Apps     │            │   AZ-2 Apps     │     │  │
│  │  │  ┌───┐  ┌───┐   │            │  ┌───┐  ┌───┐  │     │  │
│  │  │  │EC2│  │ECS│   │            │  │EC2│  │ECS│  │     │  │
│  │  │  └─┬─┘  └─┬─┘   │            │  └─┬─┘  └─┬─┘  │     │  │
│  │  └────┼──────┼─────┘            └────┼──────┼─────┘     │  │
│  │       │      │                       │      │           │  │
│  │       └───┬──┴───────────────────────┴──┬───┘           │  │
│  └───────────┼─────────────────────────────┼───────────────┘  │
│              │ Writes                      │ Reads            │
│              │                             │                  │
│  ┌───────────▼─────────────────────────────▼───────────────┐  │
│  │              ElastiCache Subnets                        │  │
│  │                                                         │  │
│  │  ┌───────────────────┐      ┌───────────────────┐     │  │
│  │  │  Primary Node     │      │  Replica Node     │     │  │
│  │  │  (AZ-1)           │─────→│  (AZ-2)           │     │  │
│  │  │                   │Sync  │                   │     │  │
│  │  │  Valkey t4g.micro │      │  Valkey t4g.micro │     │  │
│  │  │  Read + Write     │      │  Read-only        │     │  │
│  │  │  1.37 GB RAM      │      │  1.37 GB RAM      │     │  │
│  │  └───────────────────┘      └───────────────────┘     │  │
│  │                                                         │  │
│  │  If Primary fails → Replica promoted (30-60 sec) ✅    │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Multi-AZ: Survives availability zone failure ✅                │
└──────────────────────────────────────────────────────────────────┘

Cost: $30/month
HA: Yes (automatic failover in 30-60 seconds)
```

---

## Migration Path

### Phase 1: Start with Single Node (Dev/Staging)

```
Week 1-2: Initial Setup
┌────────────────────────────────────────┐
│ 1. Create ElastiCache Valkey cluster  │
│    - Instance: t4g.micro               │
│    - Nodes: 1 (single node)            │
│    - Cluster mode: Disabled            │
│                                        │
│ 2. Update application config          │
│    - REDIS_HOST=cluster-endpoint       │
│    - REDIS_PORT=6379                   │
│                                        │
│ 3. Test thoroughly                     │
│                                        │
│ Cost: $15/month                        │
└────────────────────────────────────────┘
```

### Phase 2: Upgrade to HA (Production)

```
Week 3-4: Add High Availability
┌────────────────────────────────────────┐
│ 1. Modify cluster                      │
│    - Add replica node                  │
│    - Enable Multi-AZ                   │
│                                        │
│ 2. No application changes needed       │
│    - Same endpoint                     │
│    - Automatic failover enabled        │
│                                        │
│ 3. Test failover                       │
│    - Reboot primary node               │
│    - Verify app still works (30-60s)   │
│                                        │
│ Cost increase: $15/month → $30/month   │
└────────────────────────────────────────┘
```

### Phase 3: Scale Up (If Needed)

```
Month 2+: Vertical Scaling
┌────────────────────────────────────────┐
│ If you need more memory:               │
│                                        │
│ t4g.micro  (1 GB)  → t4g.small (2 GB)  │
│ t4g.small  (2 GB)  → t4g.medium (5 GB) │
│ t4g.medium (5 GB)  → t4g.large (10 GB) │
│                                        │
│ Process:                               │
│ 1. Modify cluster (1-click)            │
│ 2. Brief downtime (5-10 min)           │
│ 3. No code changes                     │
└────────────────────────────────────────┘
```

---

## Summary & Recommendations

### For Your Two Target Scenarios:

#### Option 1: EC2 t4g.micro + Redis ($7-8/month)

**Pros:**
- ✅ Cheapest option
- ✅ Full control
- ✅ Good learning experience

**Cons:**
- ❌ 1-2 hours initial setup
- ❌ 2-4 hours/month maintenance
- ❌ No automatic failover
- ❌ Manual backups
- ❌ You handle security patching

**Best for:**
- Development/staging
- Non-critical applications
- Learning Redis
- Tight budget ($7/month is critical)

#### Option 2: ElastiCache Valkey t4g.micro - 1 node ($14-18/month)

**Pros:**
- ✅ 5-minute setup
- ✅ Zero maintenance
- ✅ Automatic backups
- ✅ Automatic patching
- ✅ Better security (VPC, encryption)
- ✅ CloudWatch monitoring included

**Cons:**
- ❌ No automatic failover (single node)
- ❌ 2× cost vs EC2

**Best for:**
- Production (non-critical apps)
- You value your time
- Want managed service benefits
- Can tolerate 5-10 min downtime if node fails

### My Recommendation

**Start here:**
```
ElastiCache Valkey t4g.micro - 1 node ($15/month)
```

**Upgrade when budget allows:**
```
ElastiCache Valkey t4g.micro - 2 nodes HA ($30/month)
```

**Why?**
- Your time is worth more than $7/month savings
- Managed service = less headaches
- Easy to upgrade to HA later
- Production-ready from day 1

### Cost-Benefit Analysis

```
EC2 Option:
  Savings: $7/month vs $15/month = $96/year
  Your time cost: 30 hours/year × $50/hr = $1,500/year
  Net cost: -$1,404/year (you LOSE money)

ElastiCache Option:
  Additional cost: $8/month = $96/year
  Your time saved: 30 hours/year × $50/hr = $1,500/year
  Net savings: +$1,404/year (you SAVE money)
```

**ElastiCache pays for itself if your time is worth more than $3/hour!**

---

## Next Steps

1. **Read this guide** ✅ (you're here!)
2. **Review** [PriceComparisons.md](./PriceComparisons.md)
3. **Check** Terraform module documentation
4. **Deploy** ElastiCache Valkey t4g.micro (1 node) for testing
5. **Test** your application integration
6. **Upgrade** to 2-node HA when ready for production

---

## Related Documentation

- [PriceComparisons.md](./PriceComparisons.md) - Detailed cost comparison
- [AWS ElastiCache Pricing](https://aws.amazon.com/elasticache/pricing/)
- [ElastiCache Best Practices](https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/BestPractices.html)

---

**Last Updated:** January 2026

