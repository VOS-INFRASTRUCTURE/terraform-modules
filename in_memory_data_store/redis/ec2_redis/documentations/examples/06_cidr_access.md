# Example 6: CIDR-Based Access Control

**Use Case:** Access from specific subnets or on-premises network via VPN  
**Instance:** t4g.micro (1 GB RAM)  
**Cost:** ~$7–8/month  
**Features:** CIDR allow-list instead of security group references

```hcl
module "redis_cidr_access" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env        = "staging"
  project_id = "myapp"

  vpc_id    = "vpc-12345678"
  subnet_id = "subnet-private-1a"

  allowed_cidr_blocks = [
    "10.0.1.0/24",   # Application subnet 1
    "10.0.2.0/24",   # Application subnet 2
    "172.16.0.0/16", # On-premises network via VPN
  ]

  redis_password = var.redis_password

  tags = {
    Access = "CIDR-based"
  }
}
```
