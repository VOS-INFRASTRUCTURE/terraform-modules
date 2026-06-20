################################################################################
# Redis Per App — main.tf
#
# The ec2_redis module handles:
#   - EC2 instance (t4g.small)
#   - App 1: installs Redis as 'redis-server', writes /etc/redis/redis.conf,
#            opens port 6379 in the security group for app1_security_group_id
#   - CloudWatch agent (metrics + logs) via user_data
#   - IAM role with SSM Session Manager access
#
# This file adds:
#   - Security group ingress for port 6380 (App 2)
#   - App 2 is configured post-deploy via scripts/01_deploy_app2.sh
################################################################################

module "redis_host" {
  source = "../../../../../in_memory_data_store/redis/ec2_redis"

  env        = var.env
  project_id = var.project_id

  # t4g.small = 2 GB RAM
  # With 2 Redis processes at 700 MB each + ~350 MB OS/process overhead = 1,750 MB total.
  instance_type    = "t4g.small"
  root_volume_size = 20  # extra space for AOF files from both processes

  # Network
  vpc_id    = var.vpc_id
  subnet_id = var.private_subnet_id

  # The module opens port 6379 for every SG in this list.
  # Pass only App 1's SG here — App 2's rule for port 6380 is added below.
  allowed_security_group_ids = [var.app1_security_group_id]

  # ── App 1 (port 6379, managed by the module) ──────────────────────
  redis_password  = random_password.app1_redis.result
  redis_port      = 6379

  # IMPORTANT: do not use "auto" — auto gives 1,536 MB for t4g.small,
  # which leaves no RAM for the second Redis process.
  redis_max_memory        = "700mb"
  redis_max_memory_policy = "allkeys-lru"
  redis_version           = "7.2"

  enable_redis_persistence = true
  enable_redis_aof         = true

  # CloudWatch is wired up inside the module's user_data — no extra config needed here
  enable_cloudwatch_monitoring = true
  enable_cloudwatch_logs       = true
  log_retention_days           = 30

  enable_ebs_encryption = true
  enable_ssh_access     = true  # SSM Session Manager — no key pair required

  tags = {
    Environment = var.env
    Purpose     = "redis-per-app-host"
    Apps        = "app1,app2"
  }
}

################################################################################
# Security group rule for App 2 (port 6380)
#
# The module only opens var.redis_port (6379).
# We add a separate ingress rule so only App 2's SG can reach port 6380.
# App 1's SG has no rule for 6380 — even a misconfigured App 1 client is
# blocked at the network layer before Redis sees the connection.
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
