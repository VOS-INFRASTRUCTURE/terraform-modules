# Example 1: Basic Development Setup

**Use Case:** Quick dev environment  
**Instance:** t4g.micro (1 GB RAM)  
**Cost:** ~$7–8/month  
**Features:** Defaults only — no password, no backups, basic monitoring

```hcl
module "redis_dev" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env        = "development"
  project_id = "myapp"

  vpc_id    = "vpc-12345678"
  subnet_id = "subnet-private-1a"

  allowed_security_group_ids = ["sg-app-servers"]
}

output "redis_info" {
  value = module.redis_dev.redis.connection
}
```
