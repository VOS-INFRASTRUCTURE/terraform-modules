# Example 9: Redis Per App (Separate Process per Application)

**Use Case:** Multiple applications sharing one EC2 host, each with its own isolated Redis process  
**Instance:** t4g.small (2 GB) for up to 3 apps — t4g.medium (4 GB) for up to 7 apps  
**Cost:** ~$14–16/month (t4g.small) shared across all apps  
**Features:** Separate port + separate password per app — misconfiguration gives a hard error, not silent data cross-contamination

> Full architecture explanation and manual post-deploy steps:
> [SeparateRedisPerApp.md](../SeparateRedisPerApp.md)

---

## Why Per-App Instead of Shared DB Numbers

With a shared Redis instance apps are separated only by DB index. A wrong `REDIS_DB` silently
connects to another app's data with no error.

With separate processes each app has its own port and password. A wrong port or password gives
an immediate `WRONGPASS` or `connection refused` — impossible to silently cross-contaminate.

---

## Step 1: Provision the EC2 Host

The module provisions the EC2 instance and installs Redis (one process on port 6379 for App 1).
Apps 2 and 3 are configured in Step 2 after the host is running.

```hcl
################################################################################
# Passwords — one per app
################################################################################

resource "random_password" "app1_redis" {
  length  = 32
  special = false  # false avoids shell-quoting issues in redis.conf
}

resource "random_password" "app2_redis" {
  length  = 32
  special = false
}

resource "random_password" "app3_redis" {
  length  = 32
  special = false
}

################################################################################
# Secrets Manager — one secret per app
################################################################################

resource "aws_secretsmanager_secret" "app1_redis" {
  name = "${var.env}-app1-redis-password"
}

resource "aws_secretsmanager_secret_version" "app1_redis" {
  secret_id     = aws_secretsmanager_secret.app1_redis.id
  secret_string = random_password.app1_redis.result
}

resource "aws_secretsmanager_secret" "app2_redis" {
  name = "${var.env}-app2-redis-password"
}

resource "aws_secretsmanager_secret_version" "app2_redis" {
  secret_id     = aws_secretsmanager_secret.app2_redis.id
  secret_string = random_password.app2_redis.result
}

resource "aws_secretsmanager_secret" "app3_redis" {
  name = "${var.env}-app3-redis-password"
}

resource "aws_secretsmanager_secret_version" "app3_redis" {
  secret_id     = aws_secretsmanager_secret.app3_redis.id
  secret_string = random_password.app3_redis.result
}

################################################################################
# S3 bucket for backups (shared across all app Redis processes)
################################################################################

resource "aws_s3_bucket" "redis_backups" {
  bucket = "${var.env}-shared-redis-backups"
}

resource "aws_s3_bucket_lifecycle_configuration" "redis_backups" {
  bucket = aws_s3_bucket.redis_backups.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"
    expiration {
      days = 30
    }
  }
}

################################################################################
# EC2 Redis host — module manages App 1 (port 6379)
# Apps 2 and 3 are added manually in Step 2
################################################################################

module "redis_host" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env           = var.env
  project_id    = "shared-redis-host"

  # t4g.small = 2 GB → 3 apps at 450 MB each + ~350 MB OS overhead = 1,700 MB total ✅
  # t4g.medium = 4 GB → up to 7 apps at 450 MB each
  instance_type    = "t4g.small"
  root_volume_size = 20  # Extra space for AOF files across all apps

  # Network
  vpc_id    = var.vpc_id
  subnet_id = var.private_subnet_id

  # Allow all three app security groups to reach this host.
  # AWS Security Group rules on each individual port are added below.
  allowed_security_group_ids = [
    var.app1_security_group_id,
    var.app2_security_group_id,
    var.app3_security_group_id,
  ]

  # App 1 — module manages this process (port 6379)
  redis_password           = random_password.app1_redis.result
  redis_port               = 6379
  redis_max_memory         = "450mb"
  redis_max_memory_policy  = "allkeys-lru"
  redis_version            = "7.2"
  enable_redis_persistence = true
  enable_redis_aof         = true

  # Monitoring
  enable_cloudwatch_monitoring = true
  enable_cloudwatch_logs       = true
  log_retention_days           = 30

  # Backups (covers App 1 RDB/AOF; Apps 2 and 3 need separate backup scripts)
  enable_automated_backups = true
  backup_s3_bucket_name    = aws_s3_bucket.redis_backups.id
  backup_schedule          = "0 2 * * *"

  enable_ssh_access     = true
  enable_ebs_encryption = true

  tags = {
    Environment = var.env
    Purpose     = "shared-redis-host"
    Apps        = "app1,app2,app3"
  }
}
```

---

## Step 2: Add App 2 and App 3 Security Group Rules

The module only opens port 6379 in the security group. Add ingress rules for ports 6380 and 6381
so only the correct app can reach its own port.

```hcl
# Retrieve the security group the module created for the Redis host
data "aws_security_group" "redis_host" {
  id = module.redis_host.redis.security_group_id
}

# App 2 — port 6380 — only App 2's security group can connect
resource "aws_security_group_rule" "app2_redis_ingress" {
  type                     = "ingress"
  from_port                = 6380
  to_port                  = 6380
  protocol                 = "tcp"
  source_security_group_id = var.app2_security_group_id
  security_group_id        = data.aws_security_group.redis_host.id
  description              = "App2 Redis (port 6380)"
}

# App 3 — port 6381 — only App 3's security group can connect
resource "aws_security_group_rule" "app3_redis_ingress" {
  type                     = "ingress"
  from_port                = 6381
  to_port                  = 6381
  protocol                 = "tcp"
  source_security_group_id = var.app3_security_group_id
  security_group_id        = data.aws_security_group.redis_host.id
  description              = "App3 Redis (port 6381)"
}
```

---

## Step 3: Configure Apps 2 and 3 on the Host

After `terraform apply`, connect to the instance via SSM and follow
[SeparateRedisPerApp.md](../SeparateRedisPerApp.md) Steps 1–4 to:

- Create `/etc/redis/app2.conf` (port 6380) and `/etc/redis/app3.conf` (port 6381)
- Create `redis-app2.service` and `redis-app3.service` systemd units
- Enable and start both services

The passwords to use in those config files come from Terraform outputs (see below).

---

## Step 4: Outputs for Application `.env` Files

```hcl
locals {
  redis_host = module.redis_host.redis.connection.host
}

# App 1
output "app1_redis" {
  value = {
    REDIS_HOST     = local.redis_host
    REDIS_PORT     = "6379"
    REDIS_DB       = "0"
    REDIS_CACHE_DB = "1"
  }
}

output "app1_redis_password" {
  value     = random_password.app1_redis.result
  sensitive = true
}

output "app1_redis_password_secret_arn" {
  value = aws_secretsmanager_secret.app1_redis.arn
}

# App 2
output "app2_redis" {
  value = {
    REDIS_HOST     = local.redis_host
    REDIS_PORT     = "6380"
    REDIS_DB       = "0"
    REDIS_CACHE_DB = "1"
  }
}

output "app2_redis_password" {
  value     = random_password.app2_redis.result
  sensitive = true
}

output "app2_redis_password_secret_arn" {
  value = aws_secretsmanager_secret.app2_redis.arn
}

# App 3
output "app3_redis" {
  value = {
    REDIS_HOST     = local.redis_host
    REDIS_PORT     = "6381"
    REDIS_DB       = "0"
    REDIS_CACHE_DB = "1"
  }
}

output "app3_redis_password" {
  value     = random_password.app3_redis.result
  sensitive = true
}

output "app3_redis_password_secret_arn" {
  value = aws_secretsmanager_secret.app3_redis.arn
}

# SSM access
output "redis_host_ssm_connect" {
  value = "aws ssm start-session --target ${module.redis_host.redis.instance.id}"
}
```

---

## Retrieving Outputs After Deploy

```bash
# Non-sensitive connection info
terraform output -json app1_redis
terraform output -json app2_redis
terraform output -json app3_redis

# Passwords (sensitive — masked in plan, visible with -raw)
terraform output -raw app1_redis_password
terraform output -raw app2_redis_password
terraform output -raw app3_redis_password

# Connect to host to add App 2 and App 3 processes
$(terraform output -raw redis_host_ssm_connect)
```

---

## Laravel `.env` Per App

Each app only knows its own port and password.
Even a copied-wrong `.env` gives `connection refused` or `WRONGPASS` — not silent data access.

**App 1:**
```env
REDIS_HOST=10.0.1.50
REDIS_PORT=6379
REDIS_PASSWORD=<app1_redis_password output>
REDIS_DB=0
REDIS_CACHE_DB=1

CACHE_STORE=redis
SESSION_DRIVER=redis
SESSION_CONNECTION=sessions
```

**App 2:**
```env
REDIS_HOST=10.0.1.50
REDIS_PORT=6380
REDIS_PASSWORD=<app2_redis_password output>
REDIS_DB=0
REDIS_CACHE_DB=1

CACHE_STORE=redis
SESSION_DRIVER=redis
SESSION_CONNECTION=sessions
```

**App 3:**
```env
REDIS_HOST=10.0.1.50
REDIS_PORT=6381
REDIS_PASSWORD=<app3_redis_password output>
REDIS_DB=0
REDIS_CACHE_DB=1

CACHE_STORE=redis
SESSION_DRIVER=redis
SESSION_CONNECTION=sessions
```

---

## Memory Budget

```
t4g.small — 2,048 MB total
├── Ubuntu OS:              ~150 MB
├── Redis process × 3:      ~150 MB  (50 MB idle each)
├── Connection overhead:     ~50 MB
├── App1 maxmemory:          450 MB  (port 6379)
├── App2 maxmemory:          450 MB  (port 6380)
└── App3 maxmemory:          450 MB  (port 6381)
                           ────────
                           1,700 MB  → 348 MB headroom ✅
```

Upgrade to `t4g.medium` (4 GB) if you need more than 3 apps or larger per-app budgets.

---

## Isolation Verification

After bringing up all three processes on the host:

```bash
REDIS_HOST=$(terraform output -json app1_redis | jq -r '.REDIS_HOST')
APP1_PASS=$(terraform output -raw app1_redis_password)
APP2_PASS=$(terraform output -raw app2_redis_password)
APP3_PASS=$(terraform output -raw app3_redis_password)

# Each port responds only to its own password
redis-cli -h $REDIS_HOST -p 6379 -a "$APP1_PASS" ping   # PONG ✅
redis-cli -h $REDIS_HOST -p 6380 -a "$APP2_PASS" ping   # PONG ✅
redis-cli -h $REDIS_HOST -p 6381 -a "$APP3_PASS" ping   # PONG ✅

# Wrong password on App 1's port → hard reject (not silent access)
redis-cli -h $REDIS_HOST -p 6379 -a "$APP2_PASS" ping
# (error) WRONGPASS invalid username-password pair ✅
```

---

## Adding a Fourth App Later

1. Generate a new password and Secrets Manager secret (same pattern as above).
2. Add a security group ingress rule for port 6382 from App 4's SG.
3. SSH/SSM into the host and follow [SeparateRedisPerApp.md § Adding a New App](../SeparateRedisPerApp.md#adding-a-new-app-later).
4. Add outputs for App 4's host, port, and password.

No changes to the existing three processes are needed.
