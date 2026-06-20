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
  description = "Pass to 02_update_cloudwatch.sh to add App 2 logs"
  value       = module.redis_host.redis.monitoring.log_group_name
}

################################################################################
# App 1 — port 6379
################################################################################

output "app1_redis_connection" {
  description = "Non-sensitive App 1 connection values — safe to export as env vars"
  value = {
    REDIS_HOST     = local.host
    REDIS_PORT     = "6379"
    REDIS_DB       = "0"
    REDIS_CACHE_DB = "1"
  }
}

output "app1_redis_password" {
  description = "App 1 Redis password — use terraform output -raw app1_redis_password"
  value       = random_password.app1_redis.result
  sensitive   = true
}

output "app1_redis_password_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the App 1 Redis password"
  value       = aws_secretsmanager_secret.app1_redis.arn
}

################################################################################
# App 2 — port 6380
################################################################################

output "app2_redis_connection" {
  description = "Non-sensitive App 2 connection values — safe to export as env vars"
  value = {
    REDIS_HOST     = local.host
    REDIS_PORT     = "6380"
    REDIS_DB       = "0"
    REDIS_CACHE_DB = "1"
  }
}

output "app2_redis_password" {
  description = "App 2 Redis password — use terraform output -raw app2_redis_password"
  value       = random_password.app2_redis.result
  sensitive   = true
}

output "app2_redis_password_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the App 2 Redis password"
  value       = aws_secretsmanager_secret.app2_redis.arn
}
