# Example 4: Custom Redis Configuration

**Use Case:** Specific Redis configuration needs (non-standard port, explicit memory policy)  
**Instance:** t4g.micro (1 GB RAM)  
**Cost:** ~$7–8/month  
**Features:** Custom port (6380), volatile-lru eviction, RDB + AOF persistence

```hcl
module "redis_custom" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env        = "staging"
  project_id = "custom-app"

  vpc_id                     = "vpc-12345678"
  subnet_id                  = "subnet-private-1a"
  allowed_security_group_ids = ["sg-app-servers"]

  redis_version           = "7.0"
  redis_port              = 6380
  redis_max_memory        = "512mb"
  redis_max_memory_policy = "volatile-lru"

  enable_redis_persistence = true
  enable_redis_aof         = true

  enable_cloudwatch_monitoring = true
  enable_cloudwatch_logs       = true
  log_retention_days           = 14

  tags = {
    CustomConfig = "true"
  }
}
```
