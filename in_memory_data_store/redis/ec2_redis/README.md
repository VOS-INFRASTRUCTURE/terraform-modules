# EC2 Redis Module

Deploy self-managed Redis server on EC2 instance with automated installation and configuration.

## Overview

This module provisions an ARM-based EC2 instance (t4g.micro default) with Redis server pre-installed and configured, including:
- ✅ Automatic Redis installation and configuration
- ✅ Security group with least-privilege access
- ✅ CloudWatch monitoring and logging
- ✅ Optional automated backups to S3
- ✅ Systems Manager access (no SSH keys needed)
- ✅ Production-ready Redis configuration

**Cost: ~$7-8/month for t4g.micro**

---

## Quick Start

### Basic Usage (Development)

```hcl
module "redis" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env        = "development"
  project_id = "myapp"

  # Network
  vpc_id    = "vpc-12345678"
  subnet_id = "subnet-private-1a"

  # Allow access from application security group
  allowed_security_group_ids = [
    "sg-app-servers"
  ]
}
```

### Production Usage with Backups

```hcl
module "redis" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env        = "production"
  project_id = "myapp"

  # Instance
  instance_type = "t4g.small"  # 2 GB RAM for production

  # Network
  vpc_id    = "vpc-12345678"
  subnet_id = "subnet-private-1a"
  allowed_security_group_ids = ["sg-app-servers"]

  # Redis configuration
  redis_password          = var.redis_password  # From AWS Secrets Manager
  enable_redis_persistence = true
  enable_redis_aof        = true  # Extra durability

  # Monitoring
  enable_cloudwatch_monitoring = true
  enable_cloudwatch_logs      = true
  log_retention_days          = 30

  # Backups
  enable_automated_backups = true
  backup_s3_bucket_name    = "my-redis-backups"
  backup_schedule          = "0 2 * * *"  # 2 AM daily

  tags = {
    Backup = "Required"
  }
}
```

---

## Features

### Instance Types Supported

| Type | RAM | vCPU | Monthly Cost | Use Case |
|------|-----|------|--------------|----------|
| `t4g.nano` | 512 MB | 2 | $3-4 | Tiny cache, testing |
| `t4g.micro` | 1 GB | 2 | **$7-8** | **Default - Dev/staging** |
| `t4g.small` | 2 GB | 2 | $14-16 | Small production |
| `t4g.medium` | 4 GB | 2 | $28-32 | Medium production |

### What Gets Installed

```
Ubuntu 22.04 ARM64
├── Redis ${var.redis_version} (6.2, 7.0, or 7.2)
├── CloudWatch Agent (if monitoring enabled)
├── SSM Agent (for Systems Manager access)
└── Automated backup script (if backups enabled)
```

### Redis Configuration Managed

- ✅ Memory limits (auto-calculated based on instance size)
- ✅ Eviction policies (LRU, LFU, etc.)
- ✅ Persistence (RDB snapshots)
- ✅ AOF (append-only file) for durability
- ✅ Password authentication
- ✅ Network binding and security
- ✅ Performance tuning

---

## Variables

### Required Variables

| Name | Description | Type |
|------|-------------|------|
| `env` | Environment name | `string` |
| `project_id` | Project identifier | `string` |
| `vpc_id` | VPC ID | `string` |
| `subnet_id` | Subnet ID (private recommended) | `string` |

### Optional Variables

| Name | Description | Default |
|------|-------------|---------|
| `instance_type` | EC2 instance type | `"t4g.micro"` |
| `redis_version` | Redis version (6.2, 7.0, 7.2) | `"7.2"` |
| `redis_port` | Redis server port | `6379` |
| `redis_password` | Redis password | `""` (no auth) |
| `redis_max_memory` | Max memory or "auto" | `"auto"` (75% of RAM) |
| `redis_max_memory_policy` | Eviction policy | `"allkeys-lru"` |
| `enable_redis_persistence` | Enable RDB snapshots | `true` |
| `enable_redis_aof` | Enable AOF | `false` |
| `allowed_security_group_ids` | Security groups that can access Redis | `[]` |
| `allowed_cidr_blocks` | CIDR blocks that can access Redis | `[]` |
| `enable_cloudwatch_monitoring` | Enable detailed monitoring | `true` |
| `enable_cloudwatch_logs` | Enable Redis logs to CloudWatch | `true` |
| `log_retention_days` | Log retention | `7` |
| `enable_ssh_access` | Enable SSM Session Manager | `true` |
| `enable_automated_backups` | Enable S3 backups | `false` |
| `backup_s3_bucket_name` | S3 bucket for backups | `""` |
| `backup_schedule` | Cron schedule for backups | `"0 2 * * *"` |
| `root_volume_size` | EBS volume size in GB | `8` |
| `enable_ebs_encryption` | Encrypt EBS volume | `true` |

See [variables.tf](./variables.tf) for complete list.

---

## Outputs

### Single Output Object

```hcl
module.redis.redis
```

Contains everything you need:

```hcl
{
  enabled = true

  # Instance details
  instance = {
    id                = "i-0123456789abcdef"
    private_ip        = "10.0.1.50"
    instance_type     = "t4g.micro"
    availability_zone = "us-east-1a"
  }

  # Connection details
  connection = {
    host              = "10.0.1.50"
    port              = 6379
    endpoint          = "10.0.1.50:6379"
    password_required = true
    redis_cli_command = "redis-cli -h 10.0.1.50 -p 6379 -a '***PASSWORD***'"
    node_js_url       = "redis://:***PASSWORD***@10.0.1.50:6379"
  }

  # Configuration
  configuration = {
    version         = "7.2"
    max_memory      = "768mb"
    eviction_policy = "allkeys-lru"
    persistence     = true
  }

  # Security
  security_group = {
    id   = "sg-0123456789abcdef"
    name = "development-myapp-redis-sg"
  }

  # Monitoring
  monitoring = {
    cloudwatch_enabled = true
    log_group_name     = "/aws/ec2/development-myapp-redis"
  }

  # Cost estimate
  estimated_cost = {
    monthly_estimate = "$7-8/month"
    breakdown = {
      ec2_instance  = "$6.50/month"
      ebs_storage   = "$0.80/month"
      data_transfer = "$0-1/month"
    }
  }

  # Access instructions
  access = {
    ssm_session      = "aws ssm start-session --target i-0123456789abcdef"
    health_check_command = "redis-cli -h 10.0.1.50 -p 6379 ping"
  }

  # Application code examples
  app_config_examples = {
    node_js = {...}
    python  = {...}
    php     = {...}
    environment_variables = {
      REDIS_HOST = "10.0.1.50"
      REDIS_PORT = "6379"
    }
  }
}
```

---

## Application Integration

### Node.js (Express/NestJS)

```javascript
// Install
npm install ioredis

// Connection
const Redis = require('ioredis');
const redis = new Redis({
  host: module.redis.redis.connection.host,
  port: module.redis.redis.connection.port,
  password: process.env.REDIS_PASSWORD,
  retryStrategy: (times) => Math.min(times * 50, 2000)
});

// Usage
await redis.set('key', 'value');
const value = await redis.get('key');
```

### Python (Django/Flask)

```python
# Install
pip install redis

# Connection
import redis
r = redis.Redis(
    host=os.environ['REDIS_HOST'],
    port=int(os.environ['REDIS_PORT']),
    password=os.environ.get('REDIS_PASSWORD'),
    decode_responses=True
)

# Usage
r.set('key', 'value')
value = r.get('key')
```

### PHP (Laravel)

```php
// Install
composer require predis/predis

// .env
REDIS_HOST=10.0.1.50
REDIS_PASSWORD=your-password
REDIS_PORT=6379

// Usage (Laravel automatically connects)
Cache::put('key', 'value', 60);
$value = Cache::get('key');
```

---

## Accessing the Instance

### Option 1: Systems Manager (Recommended - No SSH Keys)

```bash
# Connect to instance
aws ssm start-session --target i-0123456789abcdef

# Once connected, access Redis
redis-cli
redis-cli -a 'your-password'  # If password set
```

### Option 2: SSH (If key pair configured)

```bash
ssh -i /path/to/keypair.pem ubuntu@10.0.1.50

# Then access Redis
redis-cli
```

---

## Monitoring

### CloudWatch Metrics

Available metrics (if `enable_cloudwatch_monitoring = true`):
- Memory usage percentage
- Disk usage percentage
- CPU utilization
- Network in/out

### CloudWatch Logs

Redis server logs (if `enable_cloudwatch_logs = true`):
- Log group: `/aws/ec2/{env}-{project_id}-redis`
- Includes all Redis server logs
- Searchable via CloudWatch Logs Insights

**View logs:**
```bash
aws logs tail /aws/ec2/development-myapp-redis --follow
```

---

## Backups

### Manual Backup

```bash
# Connect to instance via SSM
aws ssm start-session --target i-0123456789abcdef

# Trigger Redis save
redis-cli BGSAVE

# RDB file location
/var/lib/redis/dump.rdb
```

### Automated Backups to S3

If `enable_automated_backups = true`:
- Cron job runs at specified schedule
- Triggers `BGSAVE` in Redis
- Uploads RDB file to S3
- S3 path: `s3://{bucket}/redis-backups/{env}/{project_id}/`

**Restore from backup:**
```bash
# Download from S3
aws s3 cp s3://my-backups/redis-backups/production/myapp/redis-backup-20260118.rdb /tmp/

# Stop Redis
sudo systemctl stop redis-server

# Replace RDB file
sudo cp /tmp/redis-backup-20260118.rdb /var/lib/redis/dump.rdb
sudo chown redis:redis /var/lib/redis/dump.rdb

# Start Redis
sudo systemctl start redis-server
```

---

## Security

### Best Practices Implemented

✅ **Network Isolation**
- Deployed in private subnet
- Security group restricts access to app servers only

✅ **Authentication**
- Redis password authentication supported
- Store password in AWS Secrets Manager (recommended)

✅ **Encryption**
- EBS volumes encrypted by default
- TLS/SSL can be configured (requires manual setup)

✅ **Access Control**
- IAM instance profile with least-privilege permissions
- Systems Manager for SSH-less access
- No public IP assigned

✅ **Monitoring**
- CloudWatch metrics and logs enabled
- Audit trail via CloudTrail

### Security Checklist

- [ ] Deploy in private subnet
- [ ] Set Redis password: `redis_password = var.redis_password`
- [ ] Store password in Secrets Manager, not in code
- [ ] Restrict security group to app servers only
- [ ] Enable EBS encryption: `enable_ebs_encryption = true`
- [ ] Enable CloudWatch logs for audit
- [ ] Review IAM permissions
- [ ] Disable SSH keys if using SSM

---

## Troubleshooting

### Redis Not Starting

```bash
# Connect to instance
aws ssm start-session --target i-0123456789abcdef

# Check Redis status
sudo systemctl status redis-server

# View setup logs
sudo cat /var/log/redis-setup.log

# View Redis logs
sudo tail -f /var/log/redis/redis-server.log
```

### Can't Connect from Application

1. **Check security group:**
   ```bash
   aws ec2 describe-security-groups --group-ids sg-xxx
   ```
   Verify app security group ID is in `allowed_security_group_ids`

2. **Test connection from app server:**
   ```bash
   telnet 10.0.1.50 6379
   redis-cli -h 10.0.1.50 -p 6379 ping
   ```

3. **Check Redis is listening:**
   ```bash
   sudo netstat -tlnp | grep 6379
   ```

### High Memory Usage

```bash
# Connect to Redis
redis-cli

# Check memory usage
INFO memory

# Check max memory setting
CONFIG GET maxmemory

# View eviction stats
INFO stats | grep evicted
```

**Solution:** Increase instance size or reduce `redis_max_memory`

---

## Cost Optimization

### Tips to Reduce Costs

1. **Right-size instance:**
   - Start with `t4g.micro` ($7/month)
   - Upgrade only if needed
   - Monitor memory usage

2. **Reduce log retention:**
   ```hcl
   log_retention_days = 3  # Instead of 7
   ```

3. **Disable CloudWatch monitoring if not needed:**
   ```hcl
   enable_cloudwatch_monitoring = false
   enable_cloudwatch_logs      = false
   ```

4. **Use smaller EBS volume:**
   ```hcl
   root_volume_size = 8  # Minimum needed
   ```

**Potential savings:** $1-2/month

---

## Migration from EC2 Redis to ElastiCache

When you're ready to move to managed service:

1. **Deploy ElastiCache** (don't destroy EC2 yet)
2. **Update app config** to point to ElastiCache
3. **Test thoroughly**
4. **Warm up ElastiCache** (copy hot keys if needed)
5. **Switch traffic** (update environment variables)
6. **Monitor for 24 hours**
7. **Destroy EC2 Redis** (after confirming ElastiCache works)

**Zero downtime migration possible!**

---

## Comparison: EC2 Redis vs ElastiCache

| Feature | EC2 Redis (This Module) | ElastiCache Valkey |
|---------|------------------------|-------------------|
| **Cost** | $7-8/month | $14-18/month (1 node) |
| **Setup Time** | 5-10 minutes | 5 minutes |
| **Maintenance** | You manage updates | AWS manages |
| **Backups** | Manual or custom script | Automatic |
| **High Availability** | ❌ No | ✅ Yes (with 2 nodes) |
| **Monitoring** | CloudWatch (manual setup) | Built-in |
| **Failover** | ❌ Manual | ✅ Automatic (30-60s) |
| **Best For** | Dev, staging, tight budget | Production |

**When to upgrade:**
- App becomes critical (downtime = lost money)
- Need automatic failover
- Want zero maintenance
- Budget allows 2× cost

---

## Examples

See [USAGE_EXAMPLES.md](./USAGE_EXAMPLES.md) for:
- Development setup
- Production with backups
- Custom Redis configuration
- Multi-application access
- Integration patterns

---

## Related Documentation

- [ElastiCache Complete Guide](../documentations/ElastiCache_Complete_Guide.md)
- [Single Node vs HA Quick Reference](../documentations/Single_Node_vs_HA_Quick_Reference.md)
- [Price Comparisons](../documentations/PriceComparisons.md)

---

## Support

**Issues?**
1. Check [Troubleshooting](#troubleshooting) section
2. Review CloudWatch logs
3. Check security group rules
4. Verify subnet has NAT gateway for internet access

**Cost concerns?**
- See [Cost Optimization](#cost-optimization)
- Consider [ElastiCache](../documentations/ElastiCache_Complete_Guide.md) for managed option

---

**Summary:** This module gives you a production-ready Redis server on EC2 for ~$7/month with automated setup, monitoring, and optional backups. Perfect for development, staging, or budget-constrained production workloads.

