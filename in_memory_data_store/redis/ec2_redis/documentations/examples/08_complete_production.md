# Example 8: Complete Production Setup

**Use Case:** Full production deployment with every feature enabled  
**Instance:** t4g.small (2 GB RAM)  
**Cost:** ~$14–16/month  
**Features:** Password in Secrets Manager, 6-hourly S3 backups, 90-day logs, CloudWatch alarms

```hcl
resource "random_password" "redis" {
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret" "redis_password" {
  name                    = "${var.env}-redis-password"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "redis_password" {
  secret_id     = aws_secretsmanager_secret.redis_password.id
  secret_string = random_password.redis.result
}

resource "aws_s3_bucket" "redis_backups" {
  bucket = "${var.env}-${var.project_id}-redis-backups"
}

resource "aws_s3_bucket_lifecycle_configuration" "redis_backups" {
  bucket = aws_s3_bucket.redis_backups.id

  rule {
    id     = "delete-old-backups"
    status = "Enabled"
    expiration {
      days = 30
    }
  }
}

module "redis_production" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env              = "production"
  project_id       = "myapp"
  instance_type    = "t4g.small"
  root_volume_size = 20

  vpc_id                     = "vpc-12345678"
  subnet_id                  = "subnet-private-1a"
  allowed_security_group_ids = ["sg-app-servers"]

  redis_password        = random_password.redis.result
  enable_ebs_encryption = true

  redis_version            = "7.2"
  redis_max_memory_policy  = "allkeys-lru"
  enable_redis_persistence = true
  enable_redis_aof         = true

  enable_cloudwatch_monitoring = true
  enable_cloudwatch_logs       = true
  log_retention_days           = 90

  enable_automated_backups = true
  backup_s3_bucket_name    = aws_s3_bucket.redis_backups.id
  backup_schedule          = "0 */6 * * *"

  enable_ssm_access = true

  tags = {
    Environment = "production"
    Critical    = "true"
    Backup      = "Required"
    Monitoring  = "Enhanced"
  }
}

resource "aws_cloudwatch_metric_alarm" "redis_memory_high" {
  alarm_name          = "${var.env}-redis-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUsed"
  namespace           = "EC2/Redis"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Redis memory usage above 80%"

  dimensions = {
    InstanceId = module.redis_production.redis.instance.id
  }
}

output "redis_config" {
  value = {
    host                = module.redis_production.redis.connection.host
    port                = module.redis_production.redis.connection.port
    endpoint            = module.redis_production.redis.connection.endpoint
    instance_id         = module.redis_production.redis.instance.id
    log_group           = module.redis_production.redis.monitoring.log_group_name
    password_secret_arn = aws_secretsmanager_secret.redis_password.arn
  }
}

output "redis_password" {
  value     = random_password.redis.result
  sensitive = true
}

output "redis_url" {
  value     = "redis://:${random_password.redis.result}@${module.redis_production.redis.connection.host}:${module.redis_production.redis.connection.port}"
  sensitive = true
}
```
