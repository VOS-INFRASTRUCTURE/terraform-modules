# ElastiCache Redis/Valkey Module

Deploy managed Redis or Valkey cluster on AWS ElastiCache with automatic failover, backups, and encryption.

## Overview

This module provisions AWS ElastiCache for Redis or Valkey, providing:
- ✅ Fully managed Redis/Valkey service
- ✅ Automatic failover (with HA configuration)
- ✅ Automatic backups and snapshots
- ✅ Automatic patching and updates
- ✅ Built-in monitoring and metrics
- ✅ Multi-AZ deployment
- ✅ Encryption at rest and in transit

**Default Cost: ~$14-18/month for cache.t4g.micro (1 node Valkey)**  
**HA Cost: ~$28-36/month for cache.t4g.micro (2 nodes Valkey with automatic failover)**

---

## Quick Start

### Basic Usage (Single Node - Development)

```hcl
module "redis" {
  source = "../../in_memory_data_store/redis/elasticache_redis"

  env        = "development"
  project_id = "myapp"

  # Use Valkey (30% cheaper than Redis OSS)
  engine     = "valkey"
  node_type  = "cache.t4g.micro"

  # Network
  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-private-1a", "subnet-private-1b"]

  # Allow access from application servers
  allowed_security_group_ids = ["sg-app-servers"]

  # Single node (no HA)
  num_cache_nodes = 1
}
```

### Production Usage (High Availability)

```hcl
# Generate secure auth token
resource "random_password" "redis_auth" {
  length  = 32
  special = true
}

module "redis_prod" {
  source = "../../in_memory_data_store/redis/elasticache_redis"

  env        = "production"
  project_id = "myapp"

  # Engine
  engine         = "valkey"
  engine_version = "7.1"
  node_type      = "cache.t4g.small"  # 2 GB RAM for production

  # Network
  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-private-1a", "subnet-private-1b"]
  allowed_security_group_ids = ["sg-app-servers"]

  # High Availability (2 nodes with automatic failover)
  num_cache_nodes            = 2
  automatic_failover_enabled = true
  multi_az_enabled           = true

  # Security
  auth_token                 = random_password.redis_auth.result
  at_rest_encryption_enabled = true
  transit_encryption_enabled = false  # Enable if needed (requires TLS in app)

  # Backups
  snapshot_retention_limit = 7  # Keep 7 days of backups

  tags = {
    Environment = "production"
    Critical    = "true"
  }
}

# Output connection details
output "redis_connection" {
  value = module.redis_prod.elasticache.connection
}
```

---

## Features

### Engine Options

| Engine | Cost | Compatibility | Recommendation |
|--------|------|---------------|----------------|
| **Valkey** | **30% cheaper** | Redis 7.x compatible | ✅ **Recommended** |
| Redis OSS | Standard pricing | Official Redis | Use only if needed |

**Default: Valkey** (AWS's Redis-compatible fork)

### Node Types & Costs

| Node Type | RAM | Monthly Cost (Valkey) | Monthly Cost (Redis) | Use Case |
|-----------|-----|----------------------|---------------------|----------|
| `cache.t4g.micro` | 1.37 GB | **$14-18** (1 node)<br>**$28-36** (2 nodes HA) | $20-25<br>$40-50 | **Default - Dev/small prod** |
| `cache.t4g.small` | 2.78 GB | $28-36 (1 node)<br>$52-72 (2 nodes HA) | $40-50<br>$80-100 | Medium production |
| `cache.t4g.medium` | 5.56 GB | $56-72 (1 node)<br>$104-144 (2 nodes HA) | $80-100<br>$160-200 | Large production |
| `cache.r7g.large` | 13.07 GB | Contact AWS | Contact AWS | High-performance |

### High Availability Options

| Configuration | Nodes | Failover | Downtime | Cost Multiplier |
|--------------|-------|----------|----------|-----------------|
| **Single Node** | 1 | ❌ Manual | 5-10 minutes | 1× |
| **HA (Multi-AZ)** | 2+ | ✅ Automatic | 30-60 seconds | 2×+ |

---

## Variables

### Required Variables

| Name | Description | Type |
|------|-------------|------|
| `env` | Environment name | `string` |
| `project_id` | Project identifier | `string` |
| `vpc_id` | VPC ID | `string` |
| `subnet_ids` | List of subnet IDs (minimum 2 for Multi-AZ) | `list(string)` |

### Optional Variables

| Name | Description | Default |
|------|-------------|---------|
| `engine` | Engine type: "valkey" or "redis" | `"valkey"` |
| `engine_version` | Engine version | `"7.1"` (Valkey) |
| `node_type` | Instance type | `"cache.t4g.micro"` |
| `num_cache_nodes` | Number of nodes (1 = single, 2+ = HA) | `1` |
| `automatic_failover_enabled` | Enable automatic failover | `false` |
| `multi_az_enabled` | Enable Multi-AZ | `false` |
| `port` | Redis/Valkey port | `6379` |
| `auth_token` | Password for authentication | `""` (no password) |
| `at_rest_encryption_enabled` | Encrypt data at rest | `true` |
| `transit_encryption_enabled` | Encrypt data in transit (TLS) | `false` |
| `snapshot_retention_limit` | Days to retain backups (0 = disabled) | `5` |
| `allowed_security_group_ids` | Security groups allowed to access | `[]` |
| `allowed_cidr_blocks` | CIDR blocks allowed to access | `[]` |

See [variables.tf](./variables.tf) for complete list.

---

## Outputs

### Single Output Object

```hcl
module.redis.elasticache
```

Contains everything you need:

```json
{
  "enabled": true,
  "cluster_type": "replication-group",
  
  "connection": {
    "primary_endpoint": "myapp-valkey.abc123.ng.0001.use1.cache.amazonaws.com",
    "reader_endpoint": "myapp-valkey-ro.abc123.ng.0001.use1.cache.amazonaws.com",
    "port": 6379,
    "endpoint": "myapp-valkey.abc123.ng.0001.use1.cache.amazonaws.com:6379",
    "password_required": true,
    "tls_enabled": false
  },
  
  "configuration": {
    "engine": "valkey",
    "engine_version": "7.1",
    "node_type": "cache.t4g.micro",
    "num_cache_nodes": 2
  },
  
  "high_availability": {
    "enabled": true,
    "automatic_failover_enabled": true,
    "multi_az_enabled": true,
    "failover_time": "30-60 seconds"
  },
  
  "estimated_cost": {
    "node_type": "cache.t4g.micro",
    "num_nodes": 2,
    "monthly_estimate": "28-36/month"
  },
  
  "app_config_examples": {
    "node_js": {...},
    "python": {...},
    "environment_variables": {...}
  }
}
```

---

## Application Integration

### Node.js (ioredis)

```javascript
// Install
npm install ioredis

// Connection
const Redis = require('ioredis');
const redis = new Redis({
  host: module.redis.elasticache.connection.primary_endpoint,
  port: 6379,
  password: process.env.REDIS_PASSWORD,  // If auth_token set
  retryStrategy: (times) => Math.min(times * 50, 2000)
});

// Usage
await redis.set('key', 'value');
const value = await redis.get('key');
```

### Python (redis-py)

```python
# Install
pip install redis

# Connection
import redis
r = redis.Redis(
    host=os.environ['REDIS_HOST'],
    port=6379,
    password=os.environ.get('REDIS_PASSWORD'),
    decode_responses=True
)

# Usage
r.set('key', 'value')
value = r.get('key')
```

### With TLS/SSL (if transit_encryption_enabled = true)

```javascript
// Node.js
const redis = new Redis({
  host: 'endpoint',
  port: 6379,
  password: 'password',
  tls: {
    checkServerIdentity: () => undefined
  }
});
```

```python
# Python
r = redis.Redis(
    host='endpoint',
    port=6379,
    password='password',
    ssl=True,
    ssl_cert_reqs=None
)
```

---

## High Availability Explained

### Single Node (No HA)

```
┌─────────────┐
│ Redis Node  │ ← If this fails, cache is DOWN ❌
└─────────────┘

Recovery: Manual restart (5-10 minutes)
Cost: $14-18/month (Valkey t4g.micro)
```

### Multi-Node with Automatic Failover (HA)

```
┌──────────┐      ┌──────────┐
│ Primary  │─────→│ Replica  │
│ (Write)  │ Sync │ (Read)   │
└──────────┘      └──────────┘
     ↓                  ↑
 If fails,        Auto-promoted
 replica          to primary ✅
 takes over       (30-60 seconds)

Recovery: Automatic (30-60 seconds)
Cost: $28-36/month (Valkey t4g.micro × 2)
```

**Failover Process:**
1. Primary node fails (hardware issue, AZ outage, etc.)
2. ElastiCache detects failure (15-30 seconds)
3. Replica promoted to primary (30-60 seconds total)
4. New replica created automatically
5. Applications reconnect automatically

---

## Security Best Practices

### 1. Use Auth Token (Password)

```hcl
resource "random_password" "redis" {
  length  = 32
  special = true
}

module "redis" {
  # ... other config ...
  auth_token = random_password.redis.result
}
```

### 2. Store Password in Secrets Manager

```hcl
resource "aws_secretsmanager_secret" "redis_password" {
  name = "${var.env}-redis-password"
}

resource "aws_secretsmanager_secret_version" "redis_password" {
  secret_id     = aws_secretsmanager_secret.redis_password.id
  secret_string = random_password.redis.result
}
```

### 3. Enable Encryption

```hcl
module "redis" {
  # ... other config ...
  at_rest_encryption_enabled = true  # Encrypt data on disk
  transit_encryption_enabled = true  # Encrypt data in transit (TLS)
}
```

**Note:** Enabling `transit_encryption_enabled` requires TLS in your application code.

### 4. Use Private Subnets

```hcl
module "redis" {
  # ... other config ...
  subnet_ids = [
    "subnet-private-1a",  # Private subnets only
    "subnet-private-1b"
  ]
}
```

### 5. Restrict Access via Security Groups

```hcl
module "redis" {
  # ... other config ...
  allowed_security_group_ids = [
    "sg-app-servers"  # Only allow app servers
  ]
}
```

---

## Backups & Snapshots

### Automatic Backups

```hcl
module "redis" {
  # ... other config ...
  snapshot_retention_limit = 7           # Keep 7 days
  snapshot_window          = "03:00-05:00"  # Daily 3-5 AM UTC
}
```

### Final Snapshot on Deletion

```hcl
module "redis" {
  # ... other config ...
  final_snapshot_identifier = "final"  # Creates final snapshot before delete
}
```

### Manual Snapshot

```bash
aws elasticache create-snapshot \
  --replication-group-id production-myapp-valkey \
  --snapshot-name manual-snapshot-$(date +%Y%m%d)
```

### Restore from Snapshot

```hcl
module "redis_restored" {
  source = "../../in_memory_data_store/redis/elasticache_redis"
  
  # ... other config ...
  
  # Note: Restoration requires creating new cluster from snapshot via AWS Console or CLI
}
```

---

## Monitoring

### CloudWatch Metrics (Automatic)

Available metrics:
- `CPUUtilization`
- `DatabaseMemoryUsagePercentage`
- `NetworkBytesIn/Out`
- `CurrConnections`
- `Evictions`
- `CacheHits/CacheMisses`

**View metrics:**
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/ElastiCache \
  --metric-name DatabaseMemoryUsagePercentage \
  --dimensions Name=CacheClusterId,Value=production-myapp-valkey-001 \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

### CloudWatch Alarms

```hcl
resource "aws_cloudwatch_metric_alarm" "redis_memory_high" {
  alarm_name          = "${var.env}-redis-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  
  dimensions = {
    CacheClusterId = module.redis.elasticache.identifiers.cluster_id
  }
}
```

---

## Troubleshooting

### Issue: Can't Connect from Application

1. **Check security group:**
   ```bash
   aws ec2 describe-security-groups \
     --group-ids $(terraform output -json redis | jq -r '.elasticache.security.security_group_id')
   ```

2. **Verify app security group is allowed:**
   - Ensure `allowed_security_group_ids` includes app SG

3. **Test connection:**
   ```bash
   redis-cli -h <endpoint> -p 6379 ping
   redis-cli -h <endpoint> -p 6379 -a 'password' ping  # If auth enabled
   ```

### Issue: High Memory Usage

```bash
# Connect to Redis
redis-cli -h <endpoint>

# Check memory
INFO memory

# Check eviction stats
INFO stats | grep evicted
```

**Solutions:**
- Increase node size (t4g.micro → t4g.small)
- Enable eviction: `maxmemory-policy allkeys-lru`
- Review data retention strategy

### Issue: Slow Performance

1. **Check CPU utilization** (should be < 70%)
2. **Check memory** (should be < 80%)
3. **Review slow log:**
   ```bash
   redis-cli SLOWLOG GET 10
   ```

**Solutions:**
- Scale up to larger node type
- Add read replicas
- Optimize application queries

---

## Cost Optimization

### 1. Use Valkey Instead of Redis OSS

```hcl
engine = "valkey"  # 30% cheaper than Redis OSS
```

**Savings:** ~$6/month per node

### 2. Right-Size Instances

Start with `cache.t4g.micro`, monitor, then scale up if needed.

### 3. Reduce Backup Retention

```hcl
snapshot_retention_limit = 3  # Instead of 7 days
```

### 4. Single Node for Non-Critical Apps

```hcl
num_cache_nodes = 1  # Instead of 2
```

**Savings:** 50% cost reduction (but no automatic failover)

---

## Migration from EC2 Redis

1. **Deploy ElastiCache** (don't destroy EC2 yet)
2. **Update app configuration** to point to ElastiCache
3. **Test thoroughly**
4. **Warm up cache** (optional: preload hot keys)
5. **Switch traffic** (update environment variables)
6. **Monitor** for 24-48 hours
7. **Destroy EC2 Redis** instance

**Zero downtime possible!**

---

## Examples

See [USAGE_EXAMPLES.md](./USAGE_EXAMPLES.md) for:
- Single node setup
- High availability setup
- With auth token and encryption
- Custom parameter group
- Multi-environment deployment
- Complete production setup

---

## Comparison: EC2 Redis vs ElastiCache

| Feature | EC2 Redis | ElastiCache |
|---------|-----------|-------------|
| **Cost** | $7-8/month | $14-18/month (Valkey) |
| **Setup** | 10-15 minutes | 5 minutes |
| **Maintenance** | Manual (2-4 hrs/month) | Automatic (AWS managed) |
| **Backups** | Manual scripts | Automatic |
| **HA/Failover** | ❌ Manual | ✅ Automatic (30-60s) |
| **Monitoring** | Manual setup | Built-in CloudWatch |
| **Scaling** | Requires downtime | 1-click, minimal downtime |
| **Best For** | Dev, tight budget | Production, HA required |

---

## Summary

**Start with:** Single node Valkey cache.t4g.micro ($14-18/month)  
**Upgrade to:** HA with 2 nodes when app becomes critical ($28-36/month)  

**Key Benefits:**
- ✅ Zero ops overhead (AWS manages everything)
- ✅ Automatic failover (30-60 seconds)
- ✅ Automatic backups
- ✅ Built-in monitoring
- ✅ Easy to scale

**When to Use:**
- Production applications
- Need high availability
- Want managed service
- Budget allows 2× EC2 cost

This module is production-ready with sensible defaults! 🚀

