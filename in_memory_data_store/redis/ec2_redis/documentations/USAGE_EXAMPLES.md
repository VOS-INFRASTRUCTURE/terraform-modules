# EC2 Redis - Usage Examples

## Example 1: Basic Development Setup (Minimal Configuration)

```hcl
module "redis_dev" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env        = "development"
  project_id = "myapp"

  # Network
  vpc_id    = "vpc-12345678"
  subnet_id = "subnet-private-1a"

  # Allow access from application servers
  allowed_security_group_ids = ["sg-app-servers"]
}

# Output Redis connection details
output "redis_info" {
  value = module.redis_dev.redis.connection
}
```

**Use Case:** Quick dev environment  
**Cost:** ~$7-8/month  
**Features:** Default t4g.micro, no password, basic monitoring

---

## Example 2: Production with Password and Backups

```hcl
# Store Redis password in Secrets Manager
resource "aws_secretsmanager_secret" "redis_password" {
  name = "${var.env}-redis-password"
}

resource "aws_secretsmanager_secret_version" "redis_password" {
  secret_id     = aws_secretsmanager_secret.redis_password.id
  secret_string = random_password.redis.result
}

resource "random_password" "redis" {
  length  = 32
  special = true
}

# S3 bucket for backups
resource "aws_s3_bucket" "redis_backups" {
  bucket = "${var.env}-${var.project_id}-redis-backups"
}

resource "aws_s3_bucket_versioning" "redis_backups" {
  bucket = aws_s3_bucket.redis_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Deploy Redis
module "redis_prod" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env        = "production"
  project_id = "myapp"

  # Larger instance for production
  instance_type = "t4g.small"  # 2 GB RAM

  # Network
  vpc_id    = "vpc-12345678"
  subnet_id = "subnet-private-1a"
  allowed_security_group_ids = ["sg-app-servers"]

  # Security
  redis_password = random_password.redis.result

  # Redis configuration
  redis_version            = "7.2"
  enable_redis_persistence = true
  enable_redis_aof         = true  # Extra durability for production

  # Monitoring
  enable_cloudwatch_monitoring = true
  enable_cloudwatch_logs       = true
  log_retention_days           = 30

  # Backups
  enable_automated_backups = true
  backup_s3_bucket_name    = aws_s3_bucket.redis_backups.id
  backup_schedule          = "0 2 * * *"  # 2 AM daily

  tags = {
    Environment = "production"
    Backup      = "Required"
    Critical    = "true"
  }
}

# Output connection URL (password hidden)
output "redis_connection" {
  value = {
    host     = module.redis_prod.redis.connection.host
    port     = module.redis_prod.redis.connection.port
    endpoint = module.redis_prod.redis.connection.endpoint
  }
}

# Sensitive output (password)
output "redis_full_url" {
  value     = "redis://:${random_password.redis.result}@${module.redis_prod.redis.connection.host}:${module.redis_prod.redis.connection.port}"
  sensitive = true
}
```

**Use Case:** Production app  
**Cost:** ~$14-16/month  
**Features:** Secure password, automated backups, enhanced monitoring

---

## Example 3: Multi-Application Access (Shared Redis)

```hcl
# Shared Redis for multiple applications
module "shared_redis" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env        = "staging"
  project_id = "shared-cache"

  instance_type = "t4g.medium"  # 4 GB for multiple apps

  # Network
  vpc_id    = "vpc-12345678"
  subnet_id = "subnet-private-1a"

  # Allow access from multiple app security groups
  allowed_security_group_ids = [
    "sg-app1-servers",
    "sg-app2-servers",
    "sg-app3-servers"
  ]

  # Redis configuration
  redis_password          = var.redis_password
  redis_max_memory        = "3gb"  # Leave some for OS
  redis_max_memory_policy = "allkeys-lru"  # Evict least recently used

  # Persistence
  enable_redis_persistence = true

  tags = {
    Shared = "true"
    Apps   = "app1,app2,app3"
  }
}

# Export for each application
output "redis_for_app1" {
  value = {
    REDIS_HOST = module.shared_redis.redis.connection.host
    REDIS_PORT = module.shared_redis.redis.connection.port
    REDIS_DB   = "0"  # App1 uses DB 0
  }
}

output "redis_for_app2" {
  value = {
    REDIS_HOST = module.shared_redis.redis.connection.host
    REDIS_PORT = module.shared_redis.redis.connection.port
    REDIS_DB   = "1"  # App2 uses DB 1
  }
}

output "redis_for_app3" {
  value = {
    REDIS_HOST = module.shared_redis.redis.connection.host
    REDIS_PORT = module.shared_redis.redis.connection.port
    REDIS_DB   = "2"  # App3 uses DB 2
  }
}
```

**Use Case:** Multiple apps sharing one Redis  
**Cost:** ~$28-32/month  
**Features:** Larger instance, multiple DB namespaces

---

## Example 4: Custom Redis Configuration

```hcl
module "redis_custom" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env        = "staging"
  project_id = "custom-app"

  # Network
  vpc_id    = "vpc-12345678"
  subnet_id = "subnet-private-1a"
  allowed_security_group_ids = ["sg-app-servers"]

  # Custom Redis configuration
  redis_version           = "7.0"  # Specific version
  redis_port              = 6380   # Non-standard port
  redis_max_memory        = "512mb"  # Explicit limit
  redis_max_memory_policy = "volatile-lru"  # Only evict keys with TTL

  # Persistence options
  enable_redis_persistence = true  # RDB snapshots
  enable_redis_aof         = true  # AOF for durability

  # Monitoring
  enable_cloudwatch_monitoring = true
  enable_cloudwatch_logs       = true
  log_retention_days           = 14

  tags = {
    CustomConfig = "true"
  }
}
```

**Use Case:** Specific Redis configuration needs  
**Cost:** ~$7-8/month  
**Features:** Custom port, memory policy, persistence

---

## Example 5: Minimal Cost Setup (t4g.nano)

```hcl
module "redis_tiny" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env        = "development"
  project_id = "poc"

  # Smallest instance
  instance_type = "t4g.nano"  # 512 MB RAM

  # Network
  vpc_id    = "vpc-12345678"
  subnet_id = "subnet-private-1a"
  allowed_security_group_ids = ["sg-app-servers"]

  # Minimal monitoring to save costs
  enable_cloudwatch_monitoring = false
  enable_cloudwatch_logs       = false

  # No backups
  enable_automated_backups = false

  # Minimal storage
  root_volume_size = 8

  tags = {
    Purpose = "POC"
    Cost    = "Minimal"
  }
}
```

**Use Case:** Proof of concept, minimal testing  
**Cost:** ~$3-4/month  
**Features:** Absolute minimum viable setup

---

## Example 6: Allow Access from CIDR Blocks

```hcl
module "redis_cidr_access" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env        = "staging"
  project_id = "myapp"

  # Network
  vpc_id    = "vpc-12345678"
  subnet_id = "subnet-private-1a"

  # Allow access from specific IP ranges
  allowed_cidr_blocks = [
    "10.0.1.0/24",    # Application subnet 1
    "10.0.2.0/24",    # Application subnet 2
    "172.16.0.0/16"   # On-premises network (via VPN)
  ]

  redis_password = var.redis_password

  tags = {
    Access = "CIDR-based"
  }
}
```

**Use Case:** Access from specific subnets or VPN  
**Cost:** ~$7-8/month  
**Features:** CIDR-based access control

---

## Example 7: With SSH Key Access (Development)

```hcl
# Create key pair
resource "aws_key_pair" "redis_access" {
  key_name   = "${var.env}-redis-access"
  public_key = file("~/.ssh/redis_dev.pub")
}

module "redis_ssh" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env        = "development"
  project_id = "myapp"

  # Network
  vpc_id    = "vpc-12345678"
  subnet_id = "subnet-private-1a"
  allowed_security_group_ids = ["sg-app-servers"]

  # SSH access via key pair
  key_pair_name = aws_key_pair.redis_access.key_name

  # Also enable SSM for backup access method
  enable_ssh_access = true

  tags = {
    Access = "SSH-enabled"
  }
}

# Output SSH command
output "ssh_command" {
  value = "ssh -i ~/.ssh/redis_dev ubuntu@${module.redis_ssh.redis.instance.private_ip}"
}
```

**Use Case:** Traditional SSH access for developers  
**Cost:** ~$7-8/month  
**Features:** SSH key access + SSM as backup

---

## Example 8: Complete Production Setup

```hcl
# Generate secure password
resource "random_password" "redis" {
  length  = 32
  special = true
}

# Store in Secrets Manager
resource "aws_secretsmanager_secret" "redis_password" {
  name                    = "${var.env}-redis-password"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "redis_password" {
  secret_id     = aws_secretsmanager_secret.redis_password.id
  secret_string = random_password.redis.result
}

# Backup bucket
resource "aws_s3_bucket" "redis_backups" {
  bucket = "${var.env}-${var.project_id}-redis-backups"
}

resource "aws_s3_bucket_lifecycle_configuration" "redis_backups" {
  bucket = aws_s3_bucket.redis_backups.id

  rule {
    id     = "delete-old-backups"
    status = "Enabled"

    expiration {
      days = 30  # Keep backups for 30 days
    }
  }
}

# Deploy Redis
module "redis_production" {
  source = "../../in_memory_data_store/redis/ec2_redis"

  env        = "production"
  project_id = "myapp"

  # Production-grade instance
  instance_type = "t4g.small"
  root_volume_size = 20  # Extra space for logs

  # Network
  vpc_id    = "vpc-12345678"
  subnet_id = "subnet-private-1a"
  allowed_security_group_ids = ["sg-app-servers"]

  # Security
  redis_password       = random_password.redis.result
  enable_ebs_encryption = true

  # Redis configuration
  redis_version            = "7.2"
  redis_max_memory_policy  = "allkeys-lru"
  enable_redis_persistence = true
  enable_redis_aof         = true

  # Monitoring
  enable_cloudwatch_monitoring = true
  enable_cloudwatch_logs       = true
  log_retention_days           = 90

  # Backups
  enable_automated_backups = true
  backup_s3_bucket_name    = aws_s3_bucket.redis_backups.id
  backup_schedule          = "0 */6 * * *"  # Every 6 hours

  # Access
  enable_ssh_access = true  # SSM Session Manager

  tags = {
    Environment = "production"
    Critical    = "true"
    Backup      = "Required"
    Monitoring  = "Enhanced"
  }
}

# CloudWatch Alarms
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

# Outputs for application
output "redis_config" {
  value = {
    # Public outputs (non-sensitive)
    host     = module.redis_production.redis.connection.host
    port     = module.redis_production.redis.connection.port
    endpoint = module.redis_production.redis.connection.endpoint
    
    # Instance details
    instance_id = module.redis_production.redis.instance.id
    
    # Monitoring
    log_group = module.redis_production.redis.monitoring.log_group_name
    
    # Security
    password_secret_arn = aws_secretsmanager_secret.redis_password.arn
  }
}

# Sensitive output
output "redis_password" {
  value     = random_password.redis.result
  sensitive = true
}

output "redis_url" {
  value     = "redis://:${random_password.redis.result}@${module.redis_production.redis.connection.host}:${module.redis_production.redis.connection.port}"
  sensitive = true
}
```

**Use Case:** Full production deployment  
**Cost:** ~$14-16/month  
**Features:** Everything enabled, monitoring, backups, alarms

---

## Accessing Redis After Deployment

### View Connection Details

```bash
# Get all Redis information
terraform output -json redis_info

# Get just the connection endpoint
terraform output -json redis_info | jq '.connection.endpoint'

# Get password (sensitive)
terraform output -raw redis_password
```

### Connect via SSM

```bash
# Get instance ID
INSTANCE_ID=$(terraform output -json redis_info | jq -r '.instance.id')

# Start session
aws ssm start-session --target $INSTANCE_ID

# Once connected, test Redis
redis-cli ping
redis-cli -a 'your-password' ping  # If password set
```

### Test from Application Server

```bash
# Install redis-cli on app server
sudo apt-get install redis-tools

# Get Redis host from Terraform output
REDIS_HOST=$(terraform output -json redis_info | jq -r '.connection.host')

# Test connection
redis-cli -h $REDIS_HOST ping
redis-cli -h $REDIS_HOST -a 'password' ping
```

---

## Application Integration Patterns

### Node.js with Environment Variables

```bash
# .env file
REDIS_HOST=10.0.1.50
REDIS_PORT=6379
REDIS_PASSWORD=your-secure-password
```

```javascript
// config/redis.js
const Redis = require('ioredis');

const redis = new Redis({
  host: process.env.REDIS_HOST,
  port: process.env.REDIS_PORT,
  password: process.env.REDIS_PASSWORD,
  retryStrategy: (times) => {
    const delay = Math.min(times * 50, 2000);
    return delay;
  }
});

module.exports = redis;

// usage
const redis = require('./config/redis');
await redis.set('key', 'value');
const value = await redis.get('key');
```

### Python with Secrets Manager

```python
import boto3
import redis
import json

# Get password from Secrets Manager
secrets = boto3.client('secretsmanager')
secret = secrets.get_secret_value(SecretId='production-redis-password')
password = json.loads(secret['SecretString'])

# Connect to Redis
r = redis.Redis(
    host=os.environ['REDIS_HOST'],
    port=int(os.environ['REDIS_PORT']),
    password=password,
    decode_responses=True
)

# Usage
r.set('key', 'value')
value = r.get('key')
```

---

## Cost Summary by Example

| Example | Instance | Monthly Cost | Use Case |
|---------|----------|--------------|----------|
| Example 1 | t4g.micro | $7-8 | Development |
| Example 2 | t4g.small | $14-16 | Production with backups |
| Example 3 | t4g.medium | $28-32 | Multi-app shared cache |
| Example 4 | t4g.micro | $7-8 | Custom configuration |
| Example 5 | t4g.nano | $3-4 | POC/minimal testing |
| Example 6 | t4g.micro | $7-8 | CIDR-based access |
| Example 7 | t4g.micro | $7-8 | SSH access enabled |
| Example 8 | t4g.small | $14-16 | Complete production |

---

## Next Steps

1. Choose the example that matches your use case
2. Copy the code to your Terraform configuration
3. Adjust variables for your environment
4. Run `terraform plan` to review changes
5. Run `terraform apply` to deploy
6. Test connection from your application
7. Set up monitoring and alerts

For questions, see the [main README](./README.md) or [troubleshooting guide](./README.md#troubleshooting).

