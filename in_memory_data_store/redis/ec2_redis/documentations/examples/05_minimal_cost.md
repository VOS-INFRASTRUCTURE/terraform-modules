# Example 5: Minimal Cost Setup (t4g.nano)

**Use Case:** Proof of concept, throwaway testing  
**Instance:** t4g.nano (512 MB RAM)  
**Cost:** ~$3–4/month  
**Features:** Absolute minimum — no monitoring, no backups, 8 GB disk

```hcl
module "redis_tiny" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env           = "development"
  project_id    = "poc"
  instance_type = "t4g.nano"

  vpc_id                     = "vpc-12345678"
  subnet_id                  = "subnet-private-1a"
  allowed_security_group_ids = ["sg-app-servers"]

  enable_cloudwatch_monitoring = false
  enable_cloudwatch_logs       = false
  enable_automated_backups     = false

  root_volume_size = 8

  tags = {
    Purpose = "POC"
    Cost    = "Minimal"
  }
}
```
