# Example 7: SSH Key Access (Development)

**Use Case:** Traditional SSH access for developers who need to inspect Redis directly  
**Instance:** t4g.micro (1 GB RAM)  
**Cost:** ~$7–8/month  
**Features:** EC2 key pair for SSH + SSM Session Manager as fallback

```hcl
resource "aws_key_pair" "redis_access" {
  key_name   = "${var.env}-redis-access"
  public_key = file("~/.ssh/redis_dev.pub")
}

module "redis_ssh" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env        = "development"
  project_id = "myapp"

  vpc_id                     = "vpc-12345678"
  subnet_id                  = "subnet-private-1a"
  allowed_security_group_ids = ["sg-app-servers"]

  key_name              = aws_key_pair.redis_access.key_name
  enable_ssh_key_access = true
  enable_ssm_access     = true

  tags = {
    Access = "SSH-enabled"
  }
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/redis_dev ubuntu@${module.redis_ssh.redis.instance.private_ip}"
}
```
