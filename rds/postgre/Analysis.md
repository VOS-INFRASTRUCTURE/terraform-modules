# PostgreSQL: AWS RDS (Managed) vs. EC2-Hosted (Docker/Native) — Analysis

Unlike the DynamoDB case, this is a genuine apples-to-apples comparison — both sides are real, production-capable options that exist as modules in this repo:

- **Managed:** [`rds/postgre`](main.tf) — `aws_db_instance` with engine `postgres`, `multi_az` support
- **Self-hosted:** [`databases/ec2_pgsql_arm`](../../databases/ec2_pgsql_arm/README.md) — PostgreSQL 15 natively installed on Graviton (ARM) EC2, with S3/EBS backups, Secrets Manager, CloudWatch — and its sibling [`ec2_pgsql_arm_logical_wal`](../../databases/ec2_pgsql_arm_logical_wal/) for logical replication/CDC use cases

---

## 📦 The Two Options

### 1. **AWS RDS PostgreSQL (Managed)**
**Nature:** Fully managed relational database service

**What the `rds/postgre` module gives you today:**
- Multi-AZ support (`var.multi_az`, defaults to `true`)
- Storage autoscaling (`allocated_storage` → `max_allocated_storage`)
- VPC-isolated via subnet group
- **Not yet exposed as variables:** backup retention period, storage type (gp2/gp3), Performance Insights, enhanced monitoring, parameter groups — these currently fall back to AWS/provider defaults, so double-check `backup_retention_period` explicitly if you rely on automated backups, since a missed/zero value silently disables them.

**Best for:**
- Production workloads where failover and patching should be AWS's problem
- Teams without dedicated DB/ops capacity
- Workloads needing read replicas or Multi-AZ with automatic failover (typically ~60-120s)

---

### 2. **EC2-Hosted PostgreSQL (`ec2_pgsql_arm`)**
**Nature:** Native PostgreSQL 15 on a Graviton EC2 instance, fully scripted by this module

**What it gives you:**
- Hourly `pg_dumpall` → S3 (configurable retention) + optional daily EBS snapshots + optional cross-region DR copy
- Secrets Manager-generated passwords, Session Manager access (no SSH keys)
- CloudWatch logs/metrics
- Full control over `postgresql.conf` (shared_buffers, work_mem, etc.) tuned per instance size
- ARM (Graviton) pricing: 20-25% cheaper than equivalent x86

**Best for:**
- Teams comfortable owning patching, failover, and backup verification
- Cost-sensitive workloads where the RDS management premium doesn't buy enough value
- Workloads needing OS-level access, custom extensions, or non-standard tuning RDS restricts

---

## 🔄 Side-by-Side Comparison

| Feature | RDS PostgreSQL (Managed) | EC2 PostgreSQL (`ec2_pgsql_arm`) |
|---|---|---|
| **High availability** | Multi-AZ, automatic failover (~1-2 min) | Single instance by default; HA is DIY (manual standby + failover scripting) |
| **Patching** | Automated (AWS-managed maintenance windows) | Manual (`apt`/`systemctl`, your schedule) |
| **Backups** | Automated snapshots + PITR *(once `backup_retention_period` is set)* | Hourly `pg_dumpall` to S3 + optional EBS snapshots (module-managed) |
| **Read replicas** | Native, a few clicks/config | Manual streaming replication setup |
| **Storage scaling** | Online autoscaling up to `max_allocated_storage` | Resize EBS volume + filesystem manually |
| **OS/extension access** | Restricted to RDS-supported extensions | Full root access, install anything |
| **Monitoring** | Enhanced Monitoring + Performance Insights (opt-in, extra cost) | CloudWatch logs/metrics (module-configured) |
| **Compute pricing** | On-demand or Reserved Instances, x86/Graviton (`db.*g`) | Standard EC2 pricing, Graviton by default |
| **Ops burden** | Low | Moderate-to-high (you own the instance lifecycle) |
| **Security posture** | IAM auth option, VPC, encryption at rest | Secrets Manager + IAM role scoping (module-provided), same VPC/encryption controls but self-managed |

---

## 💰 Cost Comparison (illustrative, us-east-1 on-demand — verify against current AWS pricing)

### Small workload (~2 vCPU / 8GB RAM equivalent)

| Component | RDS `db.m6g.large` (Single-AZ) | RDS `db.m6g.large` (Multi-AZ) | EC2 `m7g.large` (ec2_pgsql_arm) |
|---|---|---|---|
| Compute | ~$105/mo | ~$210/mo | $67.15/mo |
| Storage (20GB gp3) | ~$2.30/mo | ~$4.60/mo (2 copies) | $1.60/mo |
| Backups | Included up to DB size | Included up to DB size | $0.64/mo (S3) + $1.70/mo (EBS snapshots, optional) |
| Monitoring | Basic included; Performance Insights extra | Same | CloudWatch ~$2.50/mo |
| Secrets | N/A (IAM/master password) | N/A | $0.80/mo (Secrets Manager) |
| **Total** | **~$107/mo** | **~$215/mo** | **~$72-74/mo** |

**Takeaway:** Single-AZ RDS and self-hosted EC2 land in a similar ballpark once you count what the module already automates (backups, monitoring, secrets); the real cost gap opens up at **Multi-AZ**, where RDS roughly doubles compute+storage for automatic failover — a cost you'd otherwise pay for in engineering time to build (and maintain, and *test*) equivalent failover on EC2.

---

## 🎯 When to Use Each

### Use **RDS PostgreSQL** When: ⭐
✅ You need Multi-AZ automatic failover and don't want to build/maintain it yourself
✅ You need native read replicas
✅ Compliance/audit requires AWS-managed patching cadence
✅ Team has limited bandwidth for DB operations
✅ Point-in-time recovery is a hard requirement (once `backup_retention_period` is configured)

### Use **EC2 PostgreSQL (`ec2_pgsql_arm`)** When:
✅ Cost sensitivity favors Graviton EC2 pricing over the RDS management premium, especially at Multi-AZ-equivalent redundancy
✅ You need PostgreSQL extensions or OS-level tuning RDS doesn't support
✅ You need logical replication/CDC (`ec2_pgsql_arm_logical_wal`) for a use case RDS makes awkward
✅ Team already operates the MySQL/Qdrant EC2 modules in this repo and has the runbooks/tooling in place

---

## 📋 Decision Matrix

```
┌─────────────────────────────────────────────────────────┐
│           POSTGRES HOSTING DECISION                      │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  Does this need automatic Multi-AZ failover or           │
│  native read replicas?                                   │
│         │                                                │
│         ├─ Yes ──► RDS PostgreSQL (Multi-AZ)             │
│         │                                                │
│         └─ No                                            │
│              │                                            │
│              ▼                                            │
│  Does the team have bandwidth to own patching,           │
│  backup verification, and failover runbooks?              │
│         │                                                │
│         ├─ No  ──► RDS PostgreSQL (Single-AZ)            │
│         │                                                │
│         └─ Yes ──► ec2_pgsql_arm (EC2 + Graviton)        │
│                     ~20-40% cheaper, full control          │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

---

## ⚠️ Before Committing Either Way

1. **`rds/postgre` module gap:** set `backup_retention_period` explicitly (not currently a module variable) — as written, verify what the provider defaults to before trusting it for production backups.
2. **`ec2_pgsql_arm` HA gap:** the module as documented is a single instance — if Multi-AZ-equivalent HA is required, that's additional engineering (standby + failover automation) not included out of the box.
3. Get real pricing for your instance sizes and region from the [AWS Pricing Calculator](https://calculator.aws) — the figures above are illustrative, not quotes.

---

## ✅ Summary

**Default to RDS (Multi-AZ)** when failover, replicas, or low ops burden matter more than shaving ~40-50% off the compute bill — that's what the Multi-AZ price premium is buying.

**Choose `ec2_pgsql_arm`** when the team already owns EC2-hosted databases elsewhere in this repo, cost matters more than turnkey HA, or you need capabilities (extensions, logical replication, OS access) RDS restricts.

---

**Last Updated:** July 2026
