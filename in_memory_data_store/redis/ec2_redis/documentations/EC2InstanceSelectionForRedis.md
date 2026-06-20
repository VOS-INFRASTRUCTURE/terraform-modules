# Redis on EC2 — Choosing the Right Instance (Memory-Optimised)

## Why Redis Needs RAM, Not CPU

Redis is an **in-memory database** — every key lives in RAM. CPU is nearly irrelevant because:

- Redis command processing is **single-threaded** — it uses exactly **1 core**
- Additional cores only help for: AOF rewrites, lazy key eviction, network I/O threads
- A `r7g.medium` with **1 vCPU** handles **100,000+ ops/second** — that's enough for most apps

```
What Redis uses:
  RAM        ← everything lives here — this is your bottleneck
  1 CPU core ← all client commands processed here
  Network    ← every GET/SET is a round trip
  Disk       ← only for AOF/RDB persistence (background)

What Redis does NOT need:
  High vCPU  ← wasted if you buy compute-optimised instances
  GPU        ← irrelevant
  High IOPS  ← only matters if AOF write rate is very high
```

This makes Redis a perfect fit for **memory-optimised (r-series) EC2 instances** — maximum RAM, minimum CPU, lowest cost per GB of RAM on AWS.

---

## Instance Family Guide

| Family | Type | RAM:vCPU | Redis Fit | Notes |
|---|---|---|---|---|
| **`r8g`** | Memory optimised, Graviton 4 | 8 GB/vCPU | ✅ Best | Latest gen, best RAM/$ |
| **`r7g`** | Memory optimised, Graviton 3 | 8 GB/vCPU | ✅ Excellent | One gen back, proven stable |
| **`r6g`** | Memory optimised, Graviton 2 | 8 GB/vCPU | ✅ Good | Cheapest reserved rates |
| **`r7i`** | Memory optimised, Intel | 8 GB/vCPU | ✅ Good | Use only if x86 required |
| **`x2gd`** | Extra large memory + NVMe | 32 GB/vCPU | ✅ Specialised | 384 GB–3.8 TB RAM options |
| **`t4g`** | General purpose, burstable | 2 GB/vCPU | ⚠️ Dev only | CPU bursts unpredictably under load |
| **`m7g`** | General purpose, Graviton 3 | 4 GB/vCPU | ❌ Wasteful | Paying for CPU Redis doesn't use |
| **`c7g`** | Compute optimised | 2 GB/vCPU | ❌ Wrong fit | CPU-heavy, RAM-light — opposite of what Redis needs |

> ✅ **Always use `r`-series for production Redis.**  
> ✅ **Always use Graviton (`g` suffix)** — 10–20% cheaper than Intel equivalent, same or better single-thread performance.

---

## Full Instance Pricing (us-east-1, On-Demand, May 2026)

### r6g — Graviton 2 (Cheapest On-Demand, Ideal for Redis)

> On-demand Linux pricing, us-east-1, ~730 hrs/month. EU regions (eu-west-1/2/3) are ~5–10% higher.

| Instance | vCPU | RAM | Network | On-Demand/mo | 1yr Reserved/mo | 3yr Reserved/mo |
|---|---|---|---|---|---|---|
| `r6g.medium` | 1 | 8 GB | Up to 10 Gbps | **~$37** | ~$24 | ~$16 |
| `r6g.large` | 2 | 16 GB | Up to 10 Gbps | **~$74** | ~$48 | ~$32 |
| `r6g.xlarge` | 4 | 32 GB | Up to 10 Gbps | **~$147** | ~$96 | ~$65 |
| `r6g.2xlarge` | 8 | 64 GB | Up to 10 Gbps | **~$294** | ~$191 | ~$130 |
| `r6g.4xlarge` | 16 | 128 GB | Up to 10 Gbps | **~$589** | ~$383 | ~$260 |
| `r6g.8xlarge` | 32 | 256 GB | Up to 12 Gbps | **~$1,177** | ~$765 | ~$520 |
| `r6g.16xlarge` | 64 | 512 GB | 25 Gbps | **~$2,355** | ~$1,530 | ~$1,040 |
| `r6g.metal` | 64 | 512 GB | 25 Gbps | **~$2,355–2,635** | ~$1,530 | ~$1,040 |

> 💡 `r6g.medium` at **~$37/mo** is the cheapest production-grade Redis on AWS — 8 GB RAM for just over $1/day.  
> 💡 `r6g.large` at **~$74/mo** gives 16 GB — enough for 2–3 Laravel apps with separate Redis instances.

---

### r7g — Graviton 3 (~5–10% more than r6g, better network throughput)

| Instance | vCPU | RAM | Network | On-Demand/mo | 1yr Reserved/mo | 3yr Reserved/mo |
|---|---|---|---|---|---|---|
| `r7g.medium` | 1 | 8 GB | Up to 12.5 Gbps | ~$40 | ~$26 | ~$18 |
| `r7g.large` | 2 | 16 GB | Up to 12.5 Gbps | ~$79 | ~$52 | ~$35 |
| `r7g.xlarge` | 4 | 32 GB | Up to 12.5 Gbps | ~$158 | ~$103 | ~$70 |
| `r7g.2xlarge` | 8 | 64 GB | Up to 15 Gbps | ~$317 | ~$206 | ~$140 |
| `r7g.4xlarge` | 16 | 128 GB | Up to 15 Gbps | ~$634 | ~$412 | ~$280 |
| `r7g.8xlarge` | 32 | 256 GB | Up to 15 Gbps | ~$1,267 | ~$824 | ~$561 |

---

### r8g — Graviton 4 (Latest Gen, Similar Price to r6g)

| Instance | vCPU | RAM | Network | On-Demand/mo | 1yr Reserved/mo | 3yr Reserved/mo |
|---|---|---|---|---|---|---|
| `r8g.medium` | 1 | 8 GB | Up to 12.5 Gbps | ~$38 | ~$25 | ~$17 |
| `r8g.large` | 2 | 16 GB | Up to 12.5 Gbps | ~$76 | ~$49 | ~$34 |
| `r8g.xlarge` | 4 | 32 GB | Up to 12.5 Gbps | ~$151 | ~$98 | ~$67 |
| `r8g.2xlarge` | 8 | 64 GB | Up to 15 Gbps | ~$302 | ~$196 | ~$133 |
| `r8g.4xlarge` | 16 | 128 GB | 25 Gbps | ~$605 | ~$393 | ~$267 |

> 💡 All three generations are within **~5% of each other** on on-demand pricing.  
> 💡 **`r6g` often wins on 3-year reserved** due to older generation discount tiers.  
> 💡 **`r8g`** gives better Graviton 4 efficiency (lower latency, higher throughput) at nearly the same price as `r6g`.

---

## Reserved Instances — The Real Cost Story

Redis workloads are **predictable and stable** — you always need it running.
Reserved instances are a no-brainer.

### `r6g.large` (16 GB) — Cost Over Time

```
On-Demand:           $74/month   → $888/year   → $2,664 over 3 years
1-Year Reserved:     $48/month   → $576/year   (saves $312/year)
3-Year Reserved:     $32/month   → $384/year   (saves $504/year vs on-demand)
```

### `r6g.medium` (8 GB) — The Budget Option

```
On-Demand:           $37/month   → $444/year
1-Year Reserved:     $24/month   → $288/year   (saves $156/year)
3-Year Reserved:     $16/month   → $192/year   (saves $252/year)

That's 8 GB of dedicated Redis for $16/month on 3-year reserved.
```

### vs ElastiCache (corrected comparison)

```
ElastiCache cache.r6g.large (16 GB, single node):
  On-Demand:    ~$147/month   ← roughly 2× the EC2 r6g.large on-demand price
  1yr Reserved: ~$96/month

EC2 r6g.large (self-managed Redis):
  On-Demand:    ~$74/month
  1yr Reserved: ~$48/month
  3yr Reserved: ~$32/month   ← 78% cheaper than ElastiCache on-demand

Verdict:
  EC2 r6g.large on-demand ($74) ≈ ElastiCache 1yr reserved ($96)
  EC2 r6g.large 3yr reserved ($32) ≈ 1/5 the cost of ElastiCache on-demand
  Trade-off: you manage patching, backups, failover yourself.
```

---

## Sizing for Multiple Redis Instances Per Host

Redis uses **< 5% CPU even under heavy load** for a typical Laravel app workload.
The OS scheduler handles multiple low-CPU processes without contention — **CPU pinning is unnecessary**.
The only constraint that actually matters is **RAM**.

### Formula

```
RAM needed = (number of apps × maxmemory per app) + OS overhead (~300–400 MB)
```

---

### Plan A: `r6g.medium` — 4 Apps (8 GB RAM, ~$37/mo)

```
8 GB total RAM
├── OS + system:                 ~200 MB
├── 4 Redis processes (idle):    ~200 MB  (~50 MB process overhead each)
├── App1 maxmemory:            1,700 MB
├── App2 maxmemory:            1,700 MB
├── App3 maxmemory:            1,700 MB
└── App4 maxmemory:            1,700 MB
                              ─────────
                               7,200 MB used  (~800 MB headroom) ✅
```

**Per-app config:**
```ini
maxmemory 1700mb        # ~1.7 GB per Redis instance
maxmemory-policy allkeys-lru
```

**What 1.7 GB gives each app:**

| Data type | RAM per item | Capacity |
|---|---|---|
| Sessions | ~3 KB | ~566,000 active sessions |
| Cache entries (small, ~1 KB) | ~1 KB | ~1,700,000 entries |
| Cache entries (medium, ~10 KB) | ~10 KB | ~170,000 entries |
| Rate limiter counters | ~100 bytes | ~17,000,000 counters |
| Horizon queue jobs | ~5 KB | ~340,000 queued jobs |

> ✅ 1.7 GB per app is **more than enough** for most Laravel applications.

---

### Plan B: `r6g.large` — 8 Apps (16 GB RAM, ~$74/mo)

```
16 GB total RAM
├── OS + system:                 ~300 MB
├── 8 Redis processes (idle):    ~400 MB  (~50 MB each)
├── App1–8 maxmemory:          1,800 MB each × 8  =  14,400 MB
                              ─────────────────────────────────
                               15,100 MB used  (~900 MB headroom) ✅
```

**Per-app config:**
```ini
maxmemory 1800mb        # ~1.8 GB per Redis instance
maxmemory-policy allkeys-lru
```

> ✅ Still ~1.8 GB per app — almost identical capacity to Plan A, just scaled to 8 apps.

---

### Why You Don't Need CPU Pinning

```
Redis command processing:   ~1–5% CPU per instance (typical Laravel workload)
8 Redis instances total:    ~8–40% of 1 CPU core

The r6g.medium has 1 vCPU.
The r6g.large  has 2 vCPU.

Even on r6g.medium (1 vCPU) with 4 Redis instances:
  4 instances × 5% CPU = 20% of 1 core under normal load
  OS scheduler trivially handles this — no contention

CPU pinning is for:  latency-critical databases (Cassandra, Kafka) under sustained high throughput
Redis on Laravel:    not that — it's sub-millisecond get/set operations, ~100 commands/sec per app
```

**Only reconsider vCPU count if:**
- Any single Redis instance sustains **> 50,000 commands/sec** continuously
- You use `LRANGE` or `ZRANGEBYSCORE` on very large sets frequently (O(N) commands)
- AOF rewrite triggers cause noticeable latency spikes (aof-rewrite-min-size tuning fixes this first)

---

---

## Recommended Instance by Scale

| Scale | Apps | Recommended | RAM | On-Demand/mo | 1yr Reserved/mo | 3yr Reserved/mo |
|---|---|---|---|---|---|---|
| Dev / test | 1–2 | `t4g.small` | 2 GB | ~$12 | ~$8 | ~$5 |
| **Small prod** | **1–4** | **`r6g.medium`** | **8 GB** | **~$37** | **~$24** | **~$16** |
| **Medium prod** | **5–8** | **`r6g.large`** | **16 GB** | **~$74** | **~$48** | **~$32** |
| Large prod | 9–16 | `r6g.xlarge` | 32 GB | ~$147 | ~$96 | ~$65 |
| Very large | 17–32 | `r6g.2xlarge` | 64 GB | ~$294 | ~$191 | ~$130 |

---

## EBS Volume — Picking the Right Disk for AOF

Redis writes an Append-Only File (AOF) to disk as a durability log. The disk needs enough **throughput**, not IOPS.

### EBS Type Comparison

| Type | IOPS | Throughput | Cost | Verdict |
|---|---|---|---|---|
| `gp2` | 3 IOPS/GB, burst to 3,000 | 128–250 MB/s | $0.10/GB-mo | ❌ Old, avoid |
| `gp3` | 3,000 base (up to 16,000) | 125 MB/s base (up to 1,000 MB/s) | $0.08/GB-mo | ✅ Default choice |
| `io2` | Up to 64,000 | Up to 4,000 MB/s | $0.125/GB + $0.065/IOPS | ✅ Only for extreme write workloads |

### AOF Volume Sizing

```
AOF file size ≈ active dataset size × 2  (before compaction runs)

Example: r8g.xlarge with 3 apps à 8 GB maxmemory
  Worst case: 3 × 8 GB × 2 = 48 GB AOF data

Recommended: 100 GB gp3 volume  (~$8/month)
  → Plenty of headroom for AOF + RDB snapshots + OS
```

### Create and Mount the Volume

```bash
# Create a 100 GB gp3 EBS volume (AWS CLI)
aws ec2 create-volume \
  --volume-type gp3 \
  --size 100 \
  --iops 3000 \
  --throughput 125 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=redis-data}]'

# Attach (replace vol-xxx and instance ID)
aws ec2 attach-volume \
  --volume-id vol-xxxxxxxxxxxxxxxxx \
  --instance-id i-xxxxxxxxxxxxxxxxx \
  --device /dev/sdf
```

```bash
# Format and mount on the EC2 instance
sudo mkfs.ext4 /dev/nvme1n1
sudo mkdir -p /var/lib/redis

# Add to /etc/fstab (persistent across reboots)
echo '/dev/nvme1n1 /var/lib/redis ext4 defaults,noatime 0 2' | sudo tee -a /etc/fstab
sudo mount -a

# Verify
df -h /var/lib/redis
# /dev/nvme1n1  100G  1.2G  98G  2% /var/lib/redis

sudo chown -R redis:redis /var/lib/redis
```

> ✅ `noatime` — skips updating file access timestamps on every read.
> Reduces disk writes by ~10–30% on a busy Redis host with many small files.

---

## Decision Summary

```
4 apps?  →  r6g.medium (8 GB)   ~$37/mo  (~$16 on 3yr reserved)
8 apps?  →  r6g.large  (16 GB)  ~$74/mo  (~$32 on 3yr reserved)

Each app gets ~1.7–1.8 GB maxmemory → ~500,000+ sessions or ~1M+ cache entries

Traffic is predictable?
  └── YES → Buy Reserved → save 35–57%

vs ElastiCache?
  └── EC2 r6g on-demand is already ~50% cheaper than ElastiCache on-demand
  └── EC2 r6g 3yr reserved is ~78% cheaper than ElastiCache on-demand
  └── Trade-off: you manage patching, backups, and failover yourself
```

---

*Last updated: May 12, 2026*

---

*Last updated: May 12, 2026*

