# Example 3: Multi-Application Access (Shared Redis — DB Numbers)

**Use Case:** Multiple apps sharing one Redis instance using database index separation  
**Instance:** t4g.medium (4 GB RAM)  
**Cost:** ~$28–32/month  
**Features:** Larger instance, DB-index namespacing per app

> **Note:** This approach carries risk — a misconfigured `REDIS_DB` silently connects an app
> to another app's data with no error. For stronger isolation see
> [Example 9: Redis Per App](./09_redis_per_app.md), which uses separate ports and passwords.

```hcl
module "shared_redis" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env           = "staging"
  project_id    = "shared-cache"
  instance_type = "t4g.medium"

  vpc_id    = "vpc-12345678"
  subnet_id = "subnet-private-1a"

  allowed_security_group_ids = [
    "sg-app1-servers",
    "sg-app2-servers",
    "sg-app3-servers",
  ]

  redis_password          = var.redis_password
  redis_max_memory        = "3gb"
  redis_max_memory_policy = "allkeys-lru"

  enable_redis_persistence = true

  tags = {
    Shared = "true"
    Apps   = "app1 app2 app3"
  }
}

# Each app uses a different DB index
output "redis_for_app1" {
  value = {
    REDIS_HOST = module.shared_redis.redis.connection.host
    REDIS_PORT = module.shared_redis.redis.connection.port
    REDIS_DB   = "0"
  }
}

output "redis_for_app2" {
  value = {
    REDIS_HOST = module.shared_redis.redis.connection.host
    REDIS_PORT = module.shared_redis.redis.connection.port
    REDIS_DB   = "1"
  }
}

output "redis_for_app3" {
  value = {
    REDIS_HOST = module.shared_redis.redis.connection.host
    REDIS_PORT = module.shared_redis.redis.connection.port
    REDIS_DB   = "2"
  }
}
```
