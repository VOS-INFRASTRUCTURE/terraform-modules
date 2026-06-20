################################################################################
# Shared host details
################################################################################

locals {
  host = module.redis_host.redis.connection.host
}

output "redis_host_ssm" {
  description = "Paste this command to open an SSM session on the Redis host"
  value       = "aws ssm start-session --target ${module.redis_host.redis.instance.id}"
}

output "redis_host_instance_id" {
  value = module.redis_host.redis.instance.id
}

output "redis_cloudwatch_log_group" {
  description = "Pass to scripts/02_update_cloudwatch.sh to register App 2 logs"
  value       = module.redis_host.redis.monitoring.log_group_name
}

################################################################################
# App 1 — port 6379
# Password is stored in Secrets Manager (auto-configured by the module).
################################################################################

output "app1_redis_connection" {
  description = "Non-sensitive App 1 connection values — copy directly into .env"
  value = {
    REDIS_HOST              = local.host
    REDIS_PORT              = "6379"
    REDIS_DB                = "0"  # Default — Laravel Redis facade; fallback for queue/cache/session if no connection specified
    REDIS_CACHE_DB          = "1"  # Application cache — Cache::put / Cache::remember
    REDIS_SESSION_DB        = "2"  # User sessions — SESSION_DRIVER=redis
    REDIS_QUEUE_DB          = "3"  # Queue jobs — Horizon workers consume here
    REDIS_HORIZON_DB        = "4"  # Horizon metrics, failed jobs, worker status
    REDIS_SCHEDULER_LOCK_DB = "5"  # onOneServer() distributed scheduler locks
  }
}

output "app1_redis_password" {
  description = "App 1 Redis password — also available in Secrets Manager"
  value       = random_password.app1_redis.result
  sensitive   = true
}

output "app1_redis_password_secret_arn" {
  description = "ARN of the Secrets Manager secret for App 1 (use this in ECS task definitions)"
  value       = aws_secretsmanager_secret.app1_redis.arn
}

################################################################################
# App 2 — port 6380
# Password is NOT in Secrets Manager — retrieve with:
#   terraform output -raw app2_redis_password
################################################################################

output "app2_redis_connection" {
  description = "Non-sensitive App 2 connection values — copy directly into .env"
  value = {
    REDIS_HOST              = local.host
    REDIS_PORT              = "6380"
    REDIS_DB                = "0"
    REDIS_CACHE_DB          = "1"
    REDIS_SESSION_DB        = "2"
    REDIS_QUEUE_DB          = "3"
    REDIS_HORIZON_DB        = "4"
    REDIS_SCHEDULER_LOCK_DB = "5"
  }
}

output "app2_redis_password" {
  description = "App 2 Redis password — pass this to scripts/01_deploy_app2.sh"
  value       = random_password.app2_redis.result
  sensitive   = true
}
