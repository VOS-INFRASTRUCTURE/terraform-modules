################################################################################
# Redis Per App — main.tf
#
# The ec2_redis module handles:
#   - EC2 instance (r6g.medium — 8 GB RAM, memory-optimized ARM64)
#   - App 1: installs Redis as 'redis-server', writes /etc/redis/redis.conf,
#            opens port 6379 in the security group for app1_security_group_id
#   - CloudWatch agent (metrics + logs) via user_data
#   - IAM role with SSM Session Manager access
#
# This file adds:
#   - Security group ingress for port 6380 (App 2)
#   - App 2 is configured post-deploy via scripts/01_deploy_app2.sh
#
# Memory budget — r6g.medium (8,192 MB):
#   OS + system:          ~350 MB
#   Redis process × 2:   ~100 MB  (50 MB idle each)
#   App 1 maxmemory:      512 MB
#   App 2 maxmemory:      512 MB
#   Used total:         1,474 MB  — leaves ~6.6 GB free for additional apps
#   Comfortable max:   ~12 apps at 512 MB each (see add-app-template/)
################################################################################

module "redis_host" {
  source = "../../../../../in_memory_data_store/redis/ec2_redis"

  env        = var.env
  project_id = var.project_id

  base_name  = "central-redis-arm-db"

  # ── EC2 Instance Config ─────────────────────────────────────────────────────
  # r6g.medium = 8 GB RAM, memory-optimized, no CPU burst limits.
  # Ideal for a shared Redis host serving multiple apps.
  # Cost: ~$37/month (vs t4g.small at ~$13/month for 2 GB)
  instance_type    = "r6g.medium"
  root_volume_size = 20

  # Network
  vpc_id    = var.vpc_id
  subnet_id = var.private_subnet_id

  # The module opens port 6379 for every SG in this list.
  # Only App 1's SG goes here — App 2's rule (port 6380) is a separate resource below.
  allowed_security_group_ids = [var.app1_security_group_id]

  # ── App 1 (port 6379, managed by the module) ──────────────────────────────
  redis_password  = random_password.app1_redis.result
  redis_port      = 6379

  # IMPORTANT: always set this explicitly on a multi-app host.
  # The module's 'auto' value for r6g.medium would be 6,144 MB — the entire
  # available RAM for one process, leaving nothing for other apps.
  redis_max_memory        = "512mb"
  redis_max_memory_policy = "allkeys-lru"

  # The module adds the Redis.io repository automatically. Valid: 6.2, 7.0, 7.2, 7.4, 8.0
  redis_version = "8.0"

  enable_redis_persistence = true
  enable_redis_aof         = true

  # CloudWatch is wired up inside the module's user_data — no extra config needed here.
  # App 2 logs are added to the same log group via scripts/02_update_cloudwatch.sh.
  enable_cloudwatch_monitoring = true
  enable_cloudwatch_logs       = true
  log_retention_days           = 30

  enable_ebs_encryption = true
  enable_ssm_access     = true  # SSM Session Manager — no EC2 key pair needed

  tags = {
    Environment = var.env
    Purpose     = "redis-per-app-host"
    Apps        = "app1 app2"
  }
}

################################################################################
# Security group rule for App 2 (port 6380)
#
# The module only creates an ingress rule for var.redis_port (6379).
# We add a separate rule so only App 2's SG can reach port 6380.
# App 1's SG has no outbound rule for 6380 — a misconfigured App 1 client is
# blocked at the network layer before Redis even receives the connection.
################################################################################

resource "aws_security_group_rule" "app2_redis_ingress" {
  type                     = "ingress"
  from_port                = 6380
  to_port                  = 6380
  protocol                 = "tcp"
  source_security_group_id = var.app2_security_group_id
  security_group_id        = module.redis_host.redis.security_group.id
  description              = "App 2 Redis (port 6380)"
}
