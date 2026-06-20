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
- `random_password` + Secrets Manager secret per app
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
│   └── passwords.tf              ← random_password + Secrets Manager for each app
├── redis-config/
│   ├── app1.conf                 ← REFERENCE — what the module writes to /etc/redis/redis.conf
│   └── app2.conf                 ← deploy this to /etc/redis/app2.conf on the host
├── systemd/
│   └── redis-app2.service        ← deploy to /etc/systemd/system/redis-app2.service
└── scripts/
    ├── 01_deploy_app2.sh         ← run via SSM after terraform apply
    ├── 02_update_cloudwatch.sh   ← add App 2 log stream to the CW agent
    └── 03_verify.sh              ← confirm each port rejects the other app's password
```

---

## Memory Layout (t4g.small — 2 GB)

```
2,048 MB total RAM
├── Ubuntu OS:            ~200 MB
├── Redis process × 2:    ~100 MB  (50 MB idle each)
├── Headroom:             ~148 MB
├── App 1 maxmemory:       700 MB  (port 6379, managed by redis-server service)
└── App 2 maxmemory:       700 MB  (port 6380, managed by redis-app2 service)
                         ────────
                         1,848 MB  ✅ fits in 2 GB
```

> The module's `auto` memory for `t4g.small` is `1,536 MB` (75% of 2 GB).
> That leaves no room for a second process.
> Always pass `redis_max_memory = "700mb"` explicitly — never use `auto` here.

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
# All logs are under same log group, just having different stream name.
LOG_GROUP=$(terraform output -raw redis_cloudwatch_log_group)
SSM_CMD=$(terraform output -raw redis_host_ssm)
```

### 3 — Upload scripts to the host, then open SSM

```bash
# Copy scripts to S3 or use the SSM Run Document approach.
# Simplest for a one-off: paste script contents directly in the SSM session.
$SSM_CMD
```

### 4 — Run App 2 setup (inside SSM session)

```bash
# Pass the App 2 password as the first argument
sudo bash 01_deploy_app2.sh "$APP2_PASS"
```

### 5 — Add App 2 log stream to CloudWatch (inside SSM session)

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

Get the host IP from Terraform:
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
CACHE_STORE=redis
SESSION_DRIVER=redis
SESSION_CONNECTION=sessions
```

Both apps use the same `REDIS_DB=0` — no DB-index juggling needed.
A copied-wrong `.env` gets `WRONGPASS` immediately.

---

## Adding a Third App Later

1. Add `random_password.app3_redis` + Secrets Manager secret in `passwords.tf`
2. Add `aws_security_group_rule.app3_redis_ingress` for port 6381 in `main.tf`
3. Add App 3 outputs to `outputs.tf`
4. Copy `redis-config/app2.conf` → `app3.conf`, change port to 6381, dir to `app3`, password placeholder
5. Copy `systemd/redis-app2.service` → `redis-app3.service`, update references
6. On the host, run a variant of `01_deploy_app2.sh` with port 6381 and the App 3 password

No changes to App 1 or App 2 are needed.
