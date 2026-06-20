# Example 2: Production with Password and Backups

**Use Case:** Production app  
**Instance:** t4g.small (2 GB RAM)  
**Cost:** ~$14–16/month  
**Features:** Secure password in Secrets Manager, daily S3 backups, enhanced monitoring

```hcl
resource "random_password" "redis" {
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret" "redis_password" {
  name = "${var.env}-redis-password"
}

resource "aws_secretsmanager_secret_version" "redis_password" {
  secret_id     = aws_secretsmanager_secret.redis_password.id
  secret_string = random_password.redis.result
}

resource "aws_s3_bucket" "redis_backups" {
  bucket = "${var.env}-${var.project_id}-redis-backups"
}

resource "aws_s3_bucket_versioning" "redis_backups" {
  bucket = aws_s3_bucket.redis_backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

module "redis_prod" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env           = "production"
  project_id    = "myapp"
  instance_type = "t4g.small"

  vpc_id                     = "vpc-12345678"
  subnet_id                  = "subnet-private-1a"
  allowed_security_group_ids = ["sg-app-servers"]

  redis_password           = random_password.redis.result
  redis_version            = "7.2"
  enable_redis_persistence = true
  enable_redis_aof         = true

  enable_cloudwatch_monitoring = true
  enable_cloudwatch_logs       = true
  log_retention_days           = 30

  enable_automated_backups = true
  backup_s3_bucket_name    = aws_s3_bucket.redis_backups.id
  backup_schedule          = "0 2 * * *"

  tags = {
    Environment = "production"
    Backup      = "Required"
    Critical    = "true"
  }
}

output "redis_connection" {
  value = {
    host     = module.redis_prod.redis.connection.host
    port     = module.redis_prod.redis.connection.port
    endpoint = module.redis_prod.redis.connection.endpoint
  }
}

output "redis_full_url" {
  value     = "redis://:${random_password.redis.result}@${module.redis_prod.redis.connection.host}:${module.redis_prod.redis.connection.port}"
  sensitive = true
}
```
