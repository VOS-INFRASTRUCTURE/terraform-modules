# Quick Reference: 1 Node vs HA (High Availability)

## Visual Comparison

### Single Node (1 Node) - $15/month

```
         Your App
            ↓
    ┌───────────────┐
    │ Redis Node    │  ← If this fails,
    │ (Primary)     │     your cache is DOWN ❌
    │ 1.37 GB RAM   │
    └───────────────┘

Recovery: Manual restart (5-10 minutes downtime)
```

### High Availability (2+ Nodes) - $30/month

```
         Your App
        ↙        ↘
  ┌──────────┐  ┌──────────┐
  │ Primary  │→→│ Replica  │
  │ (Write)  │  │ (Read)   │
  │ 1.37 GB  │  │ 1.37 GB  │
  └──────────┘  └──────────┘
       ↓              ↑
   If fails,    Auto-promoted
   replica      to primary ✅
   takes over   (30-60 seconds)

Recovery: Automatic failover (< 1 minute downtime)
```

## Feature Comparison

| Feature | Single Node | HA (Multi-Node) |
|---------|-------------|-----------------|
| **Nodes** | 1 | 2+ (primary + replicas) |
| **Cost** | $15/month | $30/month (2 nodes) |
| **If node fails** | ❌ Cache is DOWN | ✅ Auto-failover in 30-60s |
| **Downtime** | 5-10 minutes (manual) | 30-60 seconds (automatic) |
| **Availability** | ~99% | ~99.9% |
| **Multi-AZ** | ❌ No | ✅ Yes (survives AZ failure) |
| **Read scaling** | ❌ No | ✅ Yes (replicas handle reads) |
| **Manual intervention** | ✅ Required | ❌ Not needed |
| **Production-ready** | ⚠️ For non-critical apps | ✅ Yes |

## When to Use Each

### Use Single Node If:
- ✅ Development or staging environment
- ✅ Non-critical application (can tolerate 5-10 min downtime)
- ✅ Tight budget ($15/month vs $30/month matters)
- ✅ Low traffic (< 1000 req/min)
- ✅ Cache is nice-to-have, not required

**Example:** Blog cache, development environment

### Use HA (Multi-Node) If:
- ✅ Production environment
- ✅ Critical application (downtime = lost revenue)
- ✅ High availability required (< 1 min recovery)
- ✅ High traffic (> 1000 req/min)
- ✅ Cache is essential for app functionality

**Example:** E-commerce site, payment processing, API cache

## What is a "Node"?

**1 Node** = 1 server running Redis/Valkey

```
┌─────────────────────────────────┐
│        ElastiCache Node         │
│                                 │
│  • Server instance (t4g.micro)  │
│  • 1.37 GB RAM                  │
│  • Runs Redis/Valkey            │
│  • Handles requests             │
│  • Stores cache data            │
└─────────────────────────────────┘
```

**2 Nodes (HA)** = 2 servers (primary + replica)

```
┌────────────────┐      ┌────────────────┐
│ Primary Node   │─────→│ Replica Node   │
│ • Read + Write │ Sync │ • Read-only    │
│ • 1.37 GB RAM  │      │ • 1.37 GB RAM  │
└────────────────┘      └────────────────┘
```

## What is HA (High Availability)?

**High Availability** = System stays available even when components fail

**How it works:**

1. **Normal operation:**
   - Primary handles writes
   - Replica copies data from primary
   - Replica handles read requests

2. **When primary fails:**
   - Replica detects failure (15-30 seconds)
   - Replica promotes itself to primary (30-60 seconds)
   - New replica created automatically
   - Applications reconnect automatically

3. **Total downtime:** 30-60 seconds ✅

## Cost Breakdown

### Single Node
```
ElastiCache Valkey t4g.micro (1 node):
  Instance cost:     $14.00/month
  Data transfer:     $1-2/month
  Backup storage:    $0.50/month (optional)
  ────────────────────────────────
  Total:             ~$15-17/month
```

### HA (2 Nodes)
```
ElastiCache Valkey t4g.micro (2 nodes):
  Primary instance:  $14.00/month
  Replica instance:  $14.00/month
  Data transfer:     $1-2/month
  Backup storage:    $0.50/month (optional)
  ────────────────────────────────
  Total:             ~$29-31/month
```

**HA Premium:** $15/month (~100% increase)

## Failover Time Comparison

### Single Node Failure Recovery

```
0:00 - Node fails
0:30 - Monitoring alerts you
2:00 - You investigate
5:00 - You restart node
8:00 - Node comes back online
10:00 - Application reconnects
────────────────────────────────
Total: 10 minutes downtime ❌
```

### HA Failover (Automatic)

```
0:00 - Primary fails
0:15 - Replica detects failure
0:30 - Replica promotes to primary
0:45 - DNS updated
1:00 - Application reconnects
────────────────────────────────
Total: 1 minute downtime ✅
```

## Multi-AZ Explained

**Multi-AZ** = Nodes deployed in different Availability Zones (data centers)

```
┌──────────────────────────────────────────────┐
│            AWS Region (e.g., us-east-1)      │
│                                              │
│  ┌─────────────────┐  ┌─────────────────┐  │
│  │ AZ-1 (us-east)  │  │ AZ-2 (us-west)  │  │
│  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │
│  │ │   Primary   │ │  │ │   Replica   │ │  │
│  │ │    Node     │─┼──┼→│    Node     │ │  │
│  │ └─────────────┘ │  │ └─────────────┘ │  │
│  └─────────────────┘  └─────────────────┘  │
│         ↓                       ↑           │
│    If AZ-1 fails,          AZ-2 survives   │
│    AZ-2 takes over         and continues   │
└──────────────────────────────────────────────┘

Benefits:
✅ Survives data center failure
✅ Better availability (99.9% vs 99%)
✅ Automatic geographic redundancy
```

**Single node = All in 1 AZ (if AZ fails, cache is down)**  
**HA = Nodes in different AZs (if 1 AZ fails, other continues)**

## Read Scaling with HA

**Single Node:**
```
App → Primary (Read + Write)
        ↓
   All load on 1 node
```

**HA (Multi-Node):**
```
App → Primary (Write + some reads)
   ↘
     → Replica (Reads only)
   ↗
   Distribute read load across nodes ✅
```

**Performance benefit:**  
HA can handle **2x read traffic** (primary + replica both serve reads)

## Recommendation for Your Use Case

Based on your targets:

### Starting Point: ElastiCache Valkey t4g.micro - 1 node ($15/month)

**Why start here:**
- ✅ Test the waters with managed service
- ✅ Easy to upgrade to HA later (1-click)
- ✅ Much better than EC2 + Redis for ops effort
- ✅ Production-capable for non-critical apps

### Upgrade Path: Add HA when ready ($30/month)

**Upgrade when:**
- ✅ App goes to production with paying customers
- ✅ Downtime starts costing money
- ✅ You need < 1 minute recovery time
- ✅ Budget allows 2× cost

**How to upgrade:**
1. Go to ElastiCache console
2. Select cluster
3. Click "Add replica"
4. Enable Multi-AZ
5. Done! (no code changes needed)

## Summary

| Scenario | Recommendation | Cost |
|----------|----------------|------|
| **Development/Testing** | EC2 t4g.micro + Redis | $7/month |
| **Staging (non-critical)** | ElastiCache 1 node | $15/month |
| **Production (can tolerate 5-10 min downtime)** | ElastiCache 1 node | $15/month |
| **Production (need < 1 min recovery)** | ElastiCache 2 nodes HA | $30/month |
| **Production (critical - e.g., payment)** | ElastiCache 2+ nodes HA | $30+/month |

---

**Key Takeaway:**  
Start with **1 node** to save costs and learn.  
Upgrade to **HA** when your app becomes critical and downtime = lost money.

The upgrade is **1-click, zero code changes** - so you can always add HA later! ✅

