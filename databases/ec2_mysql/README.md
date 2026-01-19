# EC2 MySQL Module - Complete Usage Guide

## Overview

This module deploys a production-ready MySQL database on EC2 using Docker, with comprehensive security features including AWS Secrets Manager for password management, automated backups, and CloudWatch monitoring.

## Features

- ✅ **Secure Password Management**: Passwords stored in AWS Secrets Manager (not Terraform state)
- ✅ **Automatic Password Generation**: 32-character random passwords generated automatically
- ✅ **Encrypted Storage**: EBS volumes encrypted at rest
- ✅ **IAM Roles**: Least-privilege IAM roles for secure AWS API access
- ✅ **CloudWatch Integration**: Comprehensive logging and metrics
- ✅ **Automated Backups**: Daily backups to S3 with retention management
- ✅ **SSH-less Access**: Systems Manager Session Manager (no SSH keys needed)
- ✅ **MySQL Hardening**: Security best practices in MySQL configuration
- ✅ **Docker Health Checks**: Automatic container health monitoring

## Quick Start

### Basic Example (Development)

```hcl
module "mysql_dev" {
  source = "../../databases/ec2_mysql"

  env        = "development"
  project_id = "myapp"

  # Instance configuration
  ami_id     = "ami-0c55b159cbfafe1f0"  # Ubuntu 22.04
  subnet_id  = "subnet-12345678"
  security_group_ids = ["sg-mysql-servers"]

  # MySQL configuration
  mysql_database = "appdb"
  mysql_user     = "appuser"
  # Passwords auto-generated and stored in Secrets Manager
}
```

### Production Example (with all features)

```hcl
module "mysql_prod" {
  source = "../../databases/ec2_mysql"

  env        = "production"
  project_id = "myapp"
  base_name  = "primary-db"

  # Instance configuration
  ami_id        = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.small"  # 2 GB RAM for production
  subnet_id     = "subnet-private-1a"
  security_group_ids = ["sg-mysql-servers"]

  # Storage
  storage_size = 50  # 50 GB
  storage_type = "gp3"
  enable_ebs_encryption = true

  # Access
  enable_ssm_access      = true
  enable_ssh_key_access  = false  # Use SSM only

  # MySQL configuration
  mysql_version      = "8.0"
  mysql_database     = "production_db"
  mysql_user         = "app_user"
  # Passwords auto-generated and stored in Secrets Manager
  
  # Performance tuning
  mysql_max_connections   = 200
  innodb_buffer_pool_size = "512M"

  # Monitoring
  enable_cloudwatch_monitoring = true
  log_retention_days          = 30

  # Backups (S3 bucket created automatically by module)
  enable_automated_backups = true
  backup_schedule          = "0 * * * *"  # Hourly backups
  backup_retention_days    = 14

  tags = {
    Environment = "production"
    Critical    = "true"
    Backup      = "Required"
  }
}

# Output connection details
output "mysql_connection" {
  value = module.mysql_prod.mysql.connection
}

# Access the auto-created backup bucket
output "backup_bucket" {
  value = module.mysql_prod.mysql.backup.s3_bucket_name
}
```

## Variables

### Required Variables

| Name | Description | Type |
|------|-------------|------|
| `env` | Environment name | `string` |
| `project_id` | Project identifier | `string` |
| `ami_id` | Ubuntu 22.04 AMI ID | `string` |
| `subnet_id` | Subnet ID (private recommended) | `string` |
| `security_group_ids` | List of security group IDs | `list(string)` |
| `mysql_database` | Database name to create | `string` |
| `mysql_user` | Non-root MySQL username | `string` |

### Optional Variables

| Name | Description | Default |
|------|-------------|---------|
| `base_name` | Base name for resources | `"mysql"` |
| `instance_type` | EC2 instance type | `"t3.micro"` |
| `storage_size` | EBS volume size (GB) | `20` |
| `storage_type` | EBS volume type | `"gp3"` |
| `enable_ebs_encryption` | Encrypt EBS volumes | `true` |
| `key_name` | SSH key pair name | `""` |
| `enable_ssh_key_access` | Enable SSH key access | `false` |
| `enable_ssm_access` | Enable SSM Session Manager | `true` |
| `mysql_version` | MySQL Docker image version | `"8.0"` |
| `mysql_root_password` | Root password (auto-generated if empty) | `""` |
| `mysql_password` | User password (auto-generated if empty) | `""` |
| `mysql_max_connections` | Max MySQL connections | `151` |
| `innodb_buffer_pool_size` | InnoDB buffer pool size | `"128M"` |
| `enable_cloudwatch_monitoring` | Enable CloudWatch | `true` |
| `log_retention_days` | Log retention days | `7` |
| `enable_automated_backups` | Enable S3 backups (creates S3 bucket) | `false` |
| `backup_schedule` | Cron schedule for backups | `"0 * * * *"` (hourly) |
| `backup_retention_days` | Backup retention days | `7` |

## Outputs

### Single Output Object

```hcl
module.mysql.mysql
```

Contains all connection details, security information, and configuration:

```json
{
  "instance": {
    "id": "i-0123456789abcdef",
    "private_ip": "10.0.1.50",
    "availability_zone": "us-east-1a"
  },
  "connection": {
    "host": "10.0.1.50",
    "port": 3306,
    "database": "appdb",
    "user": "appuser",
    "mysql_cli_command": "mysql -h 10.0.1.50 -P 3306 -u appuser -p appdb"
  },
  "secrets": {
    "root_password_secret_arn": "arn:aws:secretsmanager:...",
    "user_password_secret_arn": "arn:aws:secretsmanager:...",
    "get_user_password_command": "aws secretsmanager get-secret-value ..."
  },
  "security": { ... },
  "monitoring": { ... },
  "backup": { ... },
  "access": { ... },
  "app_config_examples": { ... }
}
```

## Security Features

### 1. Password Management

Passwords are **never stored in Terraform state** in plain text. Instead:

- Automatically generated (32 characters, random)
- Stored in AWS Secrets Manager (encrypted at rest)
- Retrieved programmatically by EC2 instance
- IAM controls who can read secrets

**Retrieve password:**
```bash
aws secretsmanager get-secret-value \
  --secret-id production/myapp/mysql/mysql-user-password \
  --query SecretString \
  --output text
```

### 2. IAM Roles (Least Privilege)

The EC2 instance has minimal IAM permissions:
- ✅ Read specific Secrets Manager secrets only
- ✅ Write to specific S3 backup bucket only
- ✅ Write CloudWatch logs
- ✅ SSM Session Manager access
- ❌ Cannot create/modify AWS resources
- ❌ Cannot access other secrets

### 3. Encryption

- **EBS Volumes**: Encrypted at rest (enabled by default)
- **Secrets Manager**: Encrypted using AWS KMS
- **S3 Backups**: Server-side encryption
- **In Transit**: TLS for Secrets Manager and S3 API calls

### 4. Access Control

**Recommended: SSM Session Manager (no SSH keys)**
```bash
aws ssm start-session --target i-0123456789abcdef
```

**Benefits:**
- No SSH keys to manage
- IAM-based access control
- All sessions logged in CloudTrail
- No port 22 in security groups

### 5. MySQL Security Hardening

```ini
# MySQL configuration applied automatically
skip-name-resolve       # Prevents DNS attacks
local-infile=0          # Prevents local file access
slow_query_log=1        # Detect performance issues
log-bin                 # Binary logging for recovery
```

## Application Integration

### Node.js (with Secrets Manager)

```javascript
const AWS = require('aws-sdk');
const mysql = require('mysql2/promise');

const secretsManager = new AWS.SecretsManager();

// Get password from Secrets Manager
const secretValue = await secretsManager.getSecretValue({
  SecretId: 'production/myapp/mysql/mysql-user-password'
}).promise();

// Connect to MySQL
const connection = await mysql.createConnection({
  host: process.env.MYSQL_HOST,
  port: 3306,
  user: process.env.MYSQL_USER,
  password: secretValue.SecretString,
  database: process.env.MYSQL_DATABASE
});

// Use connection
const [rows] = await connection.execute('SELECT * FROM users');
```

### Python (with Secrets Manager)

```python
import boto3
import pymysql
import os

# Get password from Secrets Manager
secrets = boto3.client('secretsmanager')
password = secrets.get_secret_value(
    SecretId='production/myapp/mysql/mysql-user-password'
)['SecretString']

# Connect to MySQL
connection = pymysql.connect(
    host=os.environ['MYSQL_HOST'],
    port=3306,
    user=os.environ['MYSQL_USER'],
    password=password,
    database=os.environ['MYSQL_DATABASE']
)

# Use connection
cursor = connection.cursor()
cursor.execute('SELECT * FROM users')
rows = cursor.fetchall()
```

### Environment Variables

```bash
# Set these in your application
MYSQL_HOST=10.0.1.50
MYSQL_PORT=3306
MYSQL_DATABASE=appdb
MYSQL_USER=appuser
# Password retrieved from Secrets Manager programmatically
```

## Accessing the MySQL Server

### 1. Connect to Instance (via SSM)

```bash
# Get instance ID from Terraform output
terraform output -json mysql | jq -r '.instance.id'

# Start SSM session
aws ssm start-session --target i-0123456789abcdef
```

### 2. Access MySQL Container

```bash
# Once connected to instance:

# View MySQL container status
docker ps | grep mysql-server

# View MySQL logs
docker logs mysql-server -f

# Connect to MySQL CLI (as user)
docker exec -it mysql-server mysql -u appuser -p appdb

# Connect as root
docker exec -it mysql-server mysql -u root -p
```

### 3. Get Password from Secrets Manager

```bash
# On your local machine:
aws secretsmanager get-secret-value \
  --secret-id production/myapp/mysql/mysql-user-password \
  --query SecretString \
  --output text
```

## Backups

### Automated Backups

When `enable_automated_backups = true`:
- **S3 Bucket**: Created automatically by the module (no need to create separately)
- **Schedule**: Runs hourly by default (`0 * * * *` - configurable via `backup_schedule`)
- **Naming**: Folder-based structure: `YYYY-MM-DD-database-name/HHMMSS.sql.gz`
  - Example: `2026-01-19-production_db/143022.sql.gz`
  - All hourly backups for the same day are grouped in one folder
- **Process**: Creates mysqldump of all databases → compresses with gzip → uploads to S3
- **Retention**: Managed automatically by S3 lifecycle rules based on `backup_retention_days`
- **Logs**: Check `/var/log/mysql-backup.log` for backup execution logs

**S3 Bucket Structure:**
```
s3://env-project-mysql-backups/
  mysql-backups/
    production/
      myapp/
        2026-01-19-production_db/
          010000.sql.gz  # 1 AM backup
          020000.sql.gz  # 2 AM backup
          030000.sql.gz  # 3 AM backup
          ...
          230000.sql.gz  # 11 PM backup
        2026-01-18-production_db/
          010000.sql.gz
          ...
```

### Manual Backup

```bash
# Connect to instance
aws ssm start-session --target i-0123456789abcdef

# Run backup script manually
sudo /usr/local/bin/backup_mysql.sh

# Check backup logs
tail -f /var/log/mysql-backup.log
```

### Restore from Backup

```bash
# 1. List available backups
aws s3 ls s3://production-myapp-mysql-backups/mysql-backups/production/myapp/ --recursive

# 2. Download specific backup
aws s3 cp s3://bucket/mysql-backups/production/myapp/2026-01-19-production_db/143022.sql.gz .

# 3. Extract
gunzip 143022.sql.gz

# 4. Get root password
MYSQL_ROOT_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id production/myapp/mysql/mysql-root-password \
  --query SecretString \
  --output text)

# 5. Connect to instance and restore
aws ssm start-session --target i-0123456789abcdef

# On instance:
docker exec -i mysql-server mysql -u root -p"$MYSQL_ROOT_PASSWORD" < 143022.sql
```

## Monitoring

### CloudWatch Logs

View logs:
```bash
# Setup logs
aws logs tail /aws/ec2/myapp-production-mysql-mysql/setup.log

# MySQL error logs
aws logs tail /aws/ec2/myapp-production-mysql-mysql/mysql-error.log --follow
```

### CloudWatch Metrics

- Memory usage percentage
- Disk usage percentage
- CPU utilization (if detailed monitoring enabled)

### Create Alarms

```hcl
resource "aws_cloudwatch_metric_alarm" "mysql_high_memory" {
  alarm_name          = "mysql-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUsed"
  namespace           = "EC2/MySQL"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  
  dimensions = {
    InstanceId = module.mysql.mysql.instance.id
  }
}
```

## Troubleshooting

### Issue: Can't connect to MySQL

**Check security group:**
```bash
# Ensure app security group is allowed
aws ec2 describe-security-groups --group-ids sg-mysql
```

**Test connection from app server:**
```bash
telnet 10.0.1.50 3306
mysql -h 10.0.1.50 -u appuser -p appdb
```

### Issue: Forgot password

**Retrieve from Secrets Manager:**
```bash
aws secretsmanager get-secret-value \
  --secret-id production/myapp/mysql/mysql-user-password \
  --query SecretString \
  --output text
```

### Issue: MySQL container not running

**Connect to instance and check:**
```bash
docker ps -a | grep mysql-server
docker logs mysql-server
sudo /usr/local/bin/start_mysql_container.sh
```

### Issue: High disk usage

**Check disk usage:**
```bash
df -h
docker exec mysql-server du -sh /var/lib/mysql/*
```

**Solutions:**
- Increase `storage_size` variable
- Clean up old binary logs
- Archive old data

## Cost Optimization

| Configuration | Monthly Cost |
|--------------|--------------|
| t3.micro (1 GB RAM, 20 GB storage) | $7-10 |
| t3.small (2 GB RAM, 50 GB storage) | $18-25 |
| t3.medium (4 GB RAM, 100 GB storage) | $35-45 |

**Tips to reduce costs:**
1. Use gp3 instead of io1/io2 volumes
2. Reduce CloudWatch log retention
3. Disable detailed monitoring if not needed
4. Use smaller instance type for non-production

## Security Checklist

Before deploying to production:

- [ ] Deploy in private subnet
- [ ] Use auto-generated passwords (don't set `mysql_root_password`)
- [ ] Enable EBS encryption (`enable_ebs_encryption = true`)
- [ ] Enable CloudWatch monitoring
- [ ] Enable automated backups
- [ ] Use SSM Session Manager (disable SSH keys)
- [ ] Restrict security group to application only
- [ ] Configure S3 bucket versioning for backups
- [ ] Set up CloudWatch alarms
- [ ] Test backup and restore procedure
- [ ] Document password retrieval process
- [ ] Review IAM policies

## Related Documentation

- [Security Improvements](./SECURITY_IMPROVEMENTS.md) - Detailed security features
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/)
- [Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [MySQL 8.0 Reference Manual](https://dev.mysql.com/doc/refman/8.0/en/)

---

**Module is production-ready with comprehensive security features!** 🔒

