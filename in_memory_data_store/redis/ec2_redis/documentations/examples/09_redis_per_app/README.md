# Example 9: Redis Per App

Two Redis processes on one EC2 host. Each application gets its own port, its own password,
and its own memory budget. A misconfigured app receives `WRONGPASS` or `connection refused`,
not silent access to another app's data.

---

## What the Parent Module Already Handles

The `ec2_redis` module (called from `terraform/main.tf`) handles everything below.
**Do not re-implement any of it in this example.**

| Concern | Where it lives |
|---------|----------------|
| EC2 instance provisioning | `ec2_redis/main.tf` |
| Redis installation on port 6379 | `ec2_redis/user_data.tf` — writes `/etc/redis/redis.conf`, enables `redis-server` |
| CloudWatch agent (metrics + logs) | `ec2_redis/user_data.tf` |
| IAM role for SSM Session Manager | `ec2_redis/ec2_iam_role.tf` |
| Security group + ingress on port 6379 | `ec2_redis/security_group.tf` |

**This example adds on top:**

- `aws_security_group_rule` for port 6380 (App 2)
- `random_password` + Secrets Manager secret for App 1 only
- `redis-config/app2.conf` — the Redis config for App 2
- `systemd/redis-app2.service` — systemd unit for App 2
- `scripts/` — post-deploy steps to bring App 2 online and update CloudWatch

---

## Directory Layout

```
09_redis_per_app/
├── README.md                     ← you are here
├── terraform/
│   ├── main.tf                   ← module call + SG ingress for App 2
│   ├── variables.tf
│   ├── outputs.tf
│   └── passwords.tf              ← App 1: random_password + Secrets Manager
│                                    App 2: random_password only (no Secrets Manager)
├── redis-config/
│   ├── app1.conf                 ← REFERENCE — what the module writes to /etc/redis/redis.conf
│   └── app2.conf                 ← deploy this to /etc/redis/app2.conf on the host
├── systemd/
│   └── redis-app2.service        ← deploy to /etc/systemd/system/redis-app2.service
├── scripts/
│   ├── 01_deploy_app2.sh         ← run via SSM after terraform apply
│   ├── 02_update_cloudwatch.sh   ← add App 2 log stream to the CW agent
│   └── 03_verify.sh              ← confirm each port rejects the other app's password
└── add-app-template/             ← copy this to add App 3, App 4, … later
    ├── README.md
    ├── terraform/_snippet.tf
    ├── redis-config/appN.conf
    ├── systemd/redis-appN.service
    └── scripts/deploy_appN.sh
```

---

## Instance: r6g.medium (8 GB RAM)

`r6g` is AWS's memory-optimized ARM64 family. Unlike `t4g`, it has no CPU burst limit —
performance is consistent regardless of how long the processes have been running.

At 512 MB per app, the memory budget looks like this:

```
r6g.medium — 8,192 MB total RAM
├── Ubuntu OS + system:     ~350 MB
├── Redis process × 2:      ~100 MB  (50 MB idle each)
├── App 1 maxmemory:         512 MB  (port 6379, redis-server)
└── App 2 maxmemory:         512 MB  (port 6380, redis-app2)
                           ────────
                           1,474 MB used — 6,718 MB free for additional apps

At 562 MB per app (512 MB data + 50 MB process overhead):
  2  apps →  1,474 MB used  ✅  started here
  6  apps →  3,722 MB used  ✅
  10 apps →  5,970 MB used  ✅
  12 apps →  7,094 MB used  ✅  ~1.1 GB headroom
  13 apps →  7,656 MB used  ⚠️  536 MB headroom — upgrade to r6g.large
```

> **Why not `auto` for `redis_max_memory`?**
> The module's `auto` for `r6g.medium` would set `6,144 MB` (75% of 8 GB) for App 1 alone,
> leaving no memory for any other process. Always set it explicitly on a multi-app host.

---

## Redis Version

The example uses `7.2` because the module's `user_data.tf` installs Redis via the Ubuntu 22.04
default apt repository, which provides Redis 7.x through the Redis PPA that gets set up.

Redis **7.4** and **8.0** both exist and are stable. The module validation now accepts them.
To use a newer version, the `user_data.tf` in the parent module would need to install from
the [Redis.io official repository](https://redis.io/docs/latest/operate/oss_and_stack/install/install-redis/install-redis-on-linux/)
rather than the Ubuntu default apt. That is a module-level change, not an example-level one.

---

## Database Layout (6 per app)

Every app uses the same DB numbers — no cross-app coordination needed.

| DB | Env var | Purpose |
|----|---------|---------|
| 0 | `REDIS_DB` | Default — Laravel Redis facade; fallback for queue/cache/session if no connection specified |
| 1 | `REDIS_CACHE_DB` | Application cache — `Cache::put` / `Cache::remember` |
| 2 | `REDIS_SESSION_DB` | User sessions — `SESSION_DRIVER=redis` |
| 3 | `REDIS_QUEUE_DB` | Queue jobs — Horizon workers consume here |
| 4 | `REDIS_HORIZON_DB` | Horizon metrics, failed jobs, worker status |
| 5 | `REDIS_SCHEDULER_LOCK_DB` | `onOneServer()` distributed scheduler locks |

---

## Password Strategy

| App | Password source | Secrets Manager | Why |
|-----|----------------|-----------------|-----|
| App 1 | `random_password` in Terraform | ✅ Yes | Auto-configured by module at launch; apps fetch from SM at runtime |
| App 2+ | `random_password` in Terraform | ❌ No | Manually deployed via SSM script; operator retrieves with `terraform output -raw` |

---

## Deployment Steps

### 1 — Apply Terraform

```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

This provisions the host with App 1 running on port 6379. App 2 is not yet running.

### 2 — Retrieve outputs

```bash
APP2_PASS=$(terraform output -raw app2_redis_password)
LOG_GROUP=$(terraform output -raw redis_cloudwatch_log_group)
SSM_CMD=$(terraform output -raw redis_host_ssm)
```

### 3 — Open SSM session on the host

```bash
$SSM_CMD
```

### 4 — Run App 2 setup (inside SSM session)

```bash
sudo bash 01_deploy_app2.sh "$APP2_PASS"
```

### 5 — Add App 2 log stream to CloudWatch (inside SSM session)

All logs go to the same CloudWatch log group created by the module.
App 2 just gets its own stream name (`{instance_id}/redis-app2.log`).

```bash
sudo bash 02_update_cloudwatch.sh "$LOG_GROUP"
```

### 6 — Verify isolation

```bash
APP1_PASS=$(terraform output -raw app1_redis_password)
bash 03_verify.sh "$APP1_PASS" "$APP2_PASS"
```

---

## Application `.env` Files

```bash
terraform output -json app1_redis_connection
terraform output -json app2_redis_connection
```

**App 1 `.env`:**
```env
REDIS_HOST=<REDIS_HOST from app1_redis_connection>
REDIS_PORT=6379
REDIS_PASSWORD=<app1_redis_password output>
REDIS_DB=0
REDIS_CACHE_DB=1
REDIS_SESSION_DB=2
REDIS_QUEUE_DB=3
REDIS_HORIZON_DB=4
REDIS_SCHEDULER_LOCK_DB=5
CACHE_STORE=redis
SESSION_DRIVER=redis
SESSION_CONNECTION=sessions
```

**App 2 `.env`:**
```env
REDIS_HOST=<REDIS_HOST from app2_redis_connection>
REDIS_PORT=6380
REDIS_PASSWORD=<app2_redis_password output>
REDIS_DB=0
REDIS_CACHE_DB=1
REDIS_SESSION_DB=2
REDIS_QUEUE_DB=3
REDIS_HORIZON_DB=4
REDIS_SCHEDULER_LOCK_DB=5
CACHE_STORE=redis
SESSION_DRIVER=redis
SESSION_CONNECTION=sessions
```

Both apps use identical DB numbers. A wrong `.env` gets `WRONGPASS` — never silent data access.

---

## Adding More Apps

See [`add-app-template/`](./add-app-template/README.md) for a self-contained template.
The short version:

1. Copy the Terraform snippet from `add-app-template/terraform/_snippet.tf` into `terraform/main.tf`
   (or a new `terraform/appN.tf` file) — add the SG rule, password, and outputs for the new app.
2. `terraform apply`
3. `terraform output -raw appN_redis_password` to get the password.
4. Run `add-app-template/scripts/deploy_appN.sh` via SSM with the new port and password.
5. Run `scripts/02_update_cloudwatch.sh` to register the new log stream.
6. Run `scripts/03_verify.sh` to confirm isolation.
