# DynamoDB: AWS-Managed vs. Self-Hosted (EC2 + Docker) — Analysis

## ⚠️ Read This First

There are two very different things called "DynamoDB":

1. **AWS DynamoDB** — the real, managed NoSQL service (multi-AZ, auto-scaling, backups, IAM auth).
2. **`amazon/dynamodb-local`** — an official AWS Docker image that emulates the DynamoDB API **for local development and automated testing only**. AWS's own docs are explicit that it is not a production substitute.

Running `amazon/dynamodb-local` on EC2 is **not** a self-hosted production alternative to DynamoDB the way `ec2_mysql_docker` is a self-hosted alternative to RDS MySQL. It's a single-process emulator with no built-in replication, no multi-AZ failover, no automated backups/PITR, no auto-scaling, and (by default) no real authentication — just an API-compatible endpoint backed by SQLite or in-memory storage. This analysis treats it accordingly: as a **dev/test/cost-sandbox option**, not a production competitor to managed DynamoDB.

If a production-grade self-hosted key-value/wide-column store on EC2 is actually the goal, the real candidates are ScyllaDB, Cassandra, or MongoDB — happy to write that comparison instead if that's the intent.

---

## 📦 The Two Options

### 1. **AWS DynamoDB (Managed)** ⭐ RECOMMENDED for any real workload
**Nature:** Fully managed, serverless NoSQL service

**Best for:**
- Production workloads of any size
- Unpredictable or spiky traffic (on-demand capacity)
- Teams that don't want to own database operations
- Anything touching customer data or requiring durability guarantees

**Specs:**
- Durability: Replicated across 3 AZs automatically
- Scaling: On-demand or auto-scaled provisioned capacity
- Backup: Continuous backups + point-in-time recovery (PITR), on-demand snapshots
- Security: IAM-integrated, encryption at rest by default
- Ops burden: ~Zero (no patching, no failover scripts, no capacity servers to manage)

---

### 2. **`amazon/dynamodb-local` on EC2 (Docker)**
**Nature:** Single-container DynamoDB API emulator

**Best for:**
- Dev/test environments that need a DynamoDB-compatible endpoint without AWS charges
- CI pipelines running integration tests against "DynamoDB"
- Cost-sandboxing a proof-of-concept before committing to the managed service

**Specs:**
- Durability: None — single EC2 instance, single container; instance loss = data loss unless you've built your own EBS-snapshot/backup process
- Scaling: None — single process, no sharding, no read replicas
- Backup: Manual only (you'd script EBS snapshots or `docker cp` the SQLite file yourself)
- Security: No IAM integration; auth is a dummy access key/secret by convention
- Ops burden: You own the instance, the container, patching, and any backup/HA you bolt on

---

## 🔄 Side-by-Side Comparison

| Feature | AWS DynamoDB (Managed) | `dynamodb-local` on EC2 (Docker) |
|---|---|---|
| **Production-ready** | Yes | No (AWS explicitly scopes it to dev/test) |
| **Durability** | 3-AZ replication | Single instance, single EBS volume |
| **Backups** | Continuous + PITR built-in | None (manual/DIY) |
| **Scaling** | On-demand or auto-scaled | None (single process ceiling) |
| **Auth model** | IAM (fine-grained) | Dummy credentials, no real access control |
| **Multi-region** | Global Tables available | Not supported |
| **Ops overhead** | Near zero | Full instance + container lifecycle |
| **Cost model** | Pay-per-request or provisioned capacity | EC2 instance cost only (e.g., ~$7.59/mo on t3.micro) |
| **Best for** | Production, staging | Local/CI dev, cost-sandboxing |

---

## 💰 Cost Comparison

### AWS DynamoDB (Managed, On-Demand)
- No fixed monthly minimum; billed per read/write request unit + storage
- Rough example: a low-traffic app (a few million requests/month, <5GB) often lands in the **$5–25/month** range on-demand
- Cost scales with actual usage — you don't pay for idle capacity unless using provisioned mode without auto-scaling

### `dynamodb-local` on EC2 (Docker)
- Fixed cost regardless of usage: EC2 instance only
- t3.micro: ~$7.59/month + EBS (~$1–2/month for a small volume)
- No request-based charges — but also no reliability guarantees at any price

**Takeaway:** for anything beyond trivial/dev traffic, managed DynamoDB's on-demand pricing is usually cheaper *and* safer than it looks on paper, because you're not paying for redundancy, backup tooling, or engineering time to build DIY HA around a single container.

---

## 🎯 When to Use Each

### Use **AWS DynamoDB (Managed)** When: ⭐
✅ Any production or staging environment
✅ Data must survive an instance/AZ failure
✅ You need IAM-scoped access control
✅ Traffic is unpredictable (on-demand capacity absorbs spikes)
✅ You don't want to own backup/restore tooling

### Use **`dynamodb-local` on EC2 (Docker)** When:
✅ Local development or CI integration tests need a DynamoDB-compatible endpoint
✅ Prototyping data models before provisioning the real service
✅ Cost is the only concern *and* the environment is explicitly disposable (no real data, no uptime expectation)

❌ **Do not use for:** anything with real users, real data, or an uptime/durability expectation. There's no supported migration path from `dynamodb-local`'s storage format to real DynamoDB either — moving to production later means re-writing data via the API, not a lift-and-shift.

---

## 📋 Decision Matrix

```
┌─────────────────────────────────────────────────────────┐
│           DYNAMODB OPTION SELECTION                      │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  Does this need to survive an instance/AZ failure,       │
│  or hold real user data?                                 │
│         │                                                │
│         ├─ Yes ──► AWS DynamoDB (Managed)                │
│         │          On-demand capacity to start           │
│         │                                                │
│         └─ No (local dev / CI only)                      │
│              │                                            │
│              ▼                                            │
│  ✅ dynamodb-local on EC2 (Docker)                       │
│     • Fine for dev/test                                  │
│     • Never point production traffic at it               │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

---

## ✅ Summary

**For production or anything with real data:** Use **AWS DynamoDB (Managed)**. It costs less than it appears once you account for the durability, backup, and scaling it includes by default, and there is no realistic self-hosted equivalent — `dynamodb-local` is a testing tool, not a production database.

**For local dev/CI:** `dynamodb-local` on EC2 (or, more commonly, just in a local Docker Compose stack) is fine and cheap.

**Open question:** if the actual goal is a production-grade, self-hosted, cost-controlled NoSQL store on EC2 (matching the pattern of `ec2_mysql_docker`/`ec2_qdrant_arm` elsewhere in this repo), that's a different comparison — ScyllaDB, Cassandra, or MongoDB vs. AWS DynamoDB — and should be scoped as such.

---

**Last Updated:** July 2026
