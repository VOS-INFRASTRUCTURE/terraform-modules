# AWS DynamoDB — Cost Comparison by Configuration

Scope: managed AWS DynamoDB only (no self-hosted/`dynamodb-local` comparison here — see [Analysis.md](Analysis.md) for that). This doc exists to answer two questions: **what will different configurations cost**, and **which of those configuration choices can you change later vs. which ones you're stuck with** — the DynamoDB equivalent of "RDS won't let you shrink `max_allocated_storage` later."

All rates below are US East (N. Virginia), current AWS published pricing. Verify against the [AWS Pricing Calculator](https://calculator.aws) before committing budget.

---

## 💵 Pricing Reference

| Item | Standard table class | Standard-IA table class |
|---|---|---|
| On-demand write (per million WRU) | $0.625 | $0.780 (+24.8%) |
| On-demand read, eventually consistent (per million RRU) | $0.125 | $0.155 (+24%) |
| Provisioned WCU (per hour) | $0.00065 | $0.00081 (+24.6%) |
| Provisioned RCU (per hour) | $0.00013 | $0.00016 (+23.1%) |
| Storage (per GB-month, beyond 25GB free tier) | $0.25 | $0.10 (-60%) |

Notes:
- Strongly consistent reads cost **2x** the eventually-consistent rate; transactional reads/writes cost **2x** the standard rate on top of that.
- Free tier (perpetual, not just first 12 months): 25 GB storage + 25 provisioned WCU + 25 provisioned RCU per account per region.
- Reserved provisioned capacity: **1-year term up to 54% off**, **3-year term up to 77% off** WCU/RCU-hour rates — purchased in blocks of 100 units.

---

## 📊 Example Configurations at Different Scales

Storage assumed small enough to stay near/within the free tier for tiers A/B; called out explicitly for C/D.

### A. Dev / low-traffic (100K writes, 500K reads/month, <1GB)
| Mode | Monthly cost |
|---|---|
| **On-demand (Standard)** | ~$0.13 (well under $1) |
| Provisioned (min 1 WCU/1 RCU, no autoscaling) | ~$0.02 (falls inside free tier) |

**Pick:** On-demand. The dollar difference is noise; on-demand also means zero capacity-planning effort.

### B. Small production (5M writes, 20M reads/month, 5GB)
| Mode | Monthly cost |
|---|---|
| **On-demand (Standard)** | ~$5.63 |
| Provisioned, sized to actual usage (~2 WCU, ~8 RCU sustained) | ~$1.60 |

**Pick:** Either is cheap in absolute terms. On-demand is still simpler to operate; only move to provisioned here if traffic is genuinely flat and predictable, not just currently low.

### C. Medium, steady/predictable (sustained ~50 WCU + ~150 RCU 24/7, 20GB)
| Mode | Monthly cost (compute only) |
|---|---|
| On-demand equivalent | ~$131 (writes) + ~$59 (reads) = **~$190** |
| Provisioned, autoscaled near this baseline | ~$24 (WCU) + ~$14 (RCU) = **~$38** |
| Provisioned + 1-year Reserved Capacity | **~$17–20** (up to 54% off provisioned rate) |

**Pick:** Provisioned + auto scaling. Once traffic is steady enough to provision against, on-demand is roughly **5x more expensive** for the same throughput — this is the crossover point where the "simpler" option stops being the cheap option.

### D. High, steady (sustained ~500 WCU + ~1,500 RCU 24/7, 200GB)
| Mode | Monthly cost (compute only) |
|---|---|
| On-demand equivalent | ~$1,314 (writes) + ~$591 (reads) = **~$1,905** |
| Provisioned, autoscaled near this baseline | ~$237 (WCU) + ~$139 (RCU) = **~$376** |
| Provisioned + 3-year Reserved Capacity | **~$87–95** (up to 77% off provisioned rate) |

**Pick:** Provisioned + Reserved Capacity, if you're confident this baseline will hold for the term. At this volume the gap between on-demand and reserved provisioned is roughly **20x** — the biggest lever on this whole page.

**Rule of thumb:** on-demand wins for anything spiky, new, or under a few million requests/month. Provisioned (with auto scaling) wins once traffic is steady and predictable. Reserved Capacity only makes sense once you're already confident in a provisioned baseline — it's a bet on future volume, not a starting point.

---

## 🔓 What You Can Change Later (start small, safely)

These are non-events operationally — no migration, no downtime, no data rewrite:

| Setting | How flexible |
|---|---|
| **Capacity mode** (on-demand ↔ provisioned) | On-demand → provisioned: anytime. Provisioned → on-demand: up to **4 times per rolling 24-hour window**. Switch takes a few minutes; table serves at prior throughput level during the transition. |
| **WCU/RCU values** (provisioned mode) | Freely adjustable up or down, anytime, no daily-decrease limit (that restriction existed pre-2018 and is gone — a lot of older blog posts still repeat it). |
| **Auto scaling settings** (target %, min/max) | Freely adjustable anytime. |
| **Max throughput cap** (on-demand tables) | Optional per-table/GSI cap for cost control; adjustable anytime. |
| **Table class** (Standard ↔ Standard-IA) | Switchable anytime, no data migration. |
| **Global Secondary Indexes (GSI)** | Can be **added or removed after table creation**. Adding one to an existing large table triggers a backfill that consumes WCU and takes time proportional to table size — plan for that, but it's not a redesign. |
| **Global Tables** (multi-region) | Can be enabled on an existing table later. |
| **PITR, TTL, Streams, encryption key** | All toggleable/changeable anytime with no downtime. |
| **DAX (caching layer)** | Added independently; no table changes required. |
| **Storage size** | Not a setting at all — DynamoDB storage scales automatically with no pre-allocation and **no ceiling to configure**. This is the direct answer to the RDS comparison: there's no `max_allocated_storage`-style limit here because storage was never a capacity decision you had to make up front. |

---

## 🔒 What You Cannot Change Later (get these right at creation)

| Setting | Why it's fixed |
|---|---|
| **Partition key & sort key (key schema)** | Immutable for the life of the table. Changing it means creating a new table with the new schema and migrating data yourself (export/rewrite, not a native "alter"). This is the one true equivalent of a hard ceiling — worse than RDS's storage limit, since it's not resizable at all, only replaceable. |
| **Local Secondary Indexes (LSI)** | Must be defined at table creation; cannot be added, removed, or modified afterward. A table with an LSI is also capped at **10GB per partition key value**. Prefer GSIs unless you specifically need LSI's strongly-consistent-read behavior — GSIs avoid both restrictions. |
| **Reserved Capacity purchase** | A financial commitment (1 or 3 years), non-refundable, non-transferable across regions/accounts. You can still switch the table to on-demand afterward, but you've already paid for the reserved units regardless of use — treat this as a bet on a baseline you're already confident in, not a way to find one. |

---

## ✅ Recommendation

1. **Start on-demand, Standard table class.** No capacity planning, no risk of under-provisioning, cheap at low volume.
2. **Design the key schema carefully up front** — this is the one decision that isn't cheaply reversible. Model access patterns before creating the table; use GSIs (not LSIs) for secondary access patterns so you retain flexibility.
3. **Watch CloudWatch `ConsumedWriteCapacityUnits`/`ConsumedReadCapacityUnits`** once live. If usage settles into a steady, predictable baseline (tier C/D territory above), switch to provisioned + auto scaling — that's a config change, not a migration.
4. **Only buy Reserved Capacity once the provisioned baseline has held steady for a while** — it's the deepest discount, but it's a commitment, not a starting posture.

---

**Last Updated:** July 2026

Sources:
- [Amazon DynamoDB Pricing](https://aws.amazon.com/dynamodb/pricing/)
- [DynamoDB On-Demand Pricing](https://aws.amazon.com/dynamodb/pricing/on-demand/)
- [DynamoDB Provisioned Pricing](https://aws.amazon.com/dynamodb/pricing/provisioned/)
- [Considerations when switching capacity modes](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/switching.capacitymode.html)
- [Core components of Amazon DynamoDB (keys, LSI/GSI)](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.CoreComponents.html)
