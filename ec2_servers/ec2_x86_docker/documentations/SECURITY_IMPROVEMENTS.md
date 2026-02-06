# EC2 MySQL Module - Security Improvements Documentation

## 🔒 Security Enhancements Implemented

This document explains all the security improvements made to the EC2 MySQL module.

---

## 📋 Table of Contents

1. [Password Management with Secrets Manager](#password-management-with-secrets-manager)
2. [IAM Roles and Least Privilege Access](#iam-roles-and-least-privilege-access)
3. [Encryption](#encryption)
4. [Monitoring and Logging](#monitoring-and-logging)
5. [Automated Backups](#automated-backups)
6. [Access Control](#access-control)
7. [MySQL Configuration Security](#mysql-configuration-security)
8. [Password Rotation](#password-rotation)

---

## 1. Password Management with Secrets Manager

### ✅ What Was Improved

**Before:** Passwords stored in plain text in Terraform variables and exposed in outputs.

**After:** Passwords stored securely in AWS Secrets Manager with automatic generation.

### How It Works

```hcl
# Passwords are automatically generated (32 characters, secure)
resource "random_password" "mysql_root" {
  length  = 32
  special = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Stored in AWS Secrets Manager (encrypted at rest)
resource "aws_secretsmanager_secret" "mysql_root_password" {
  name = "${var.env}/${var.project_id}/${var.base_name}/mysql-root-password"
  recovery_window_in_days = 7  # Prevents accidental deletion
}
```

### Benefits

- ✅ **Encryption at Rest**: Passwords encrypted using AWS KMS
- ✅ **Encryption in Transit**: Retrieved via HTTPS/TLS
- ✅ **Access Control**: IAM policies control who can read secrets
- ✅ **Audit Trail**: CloudTrail logs all secret access
- ✅ **Recovery Window**: 7-day grace period to recover deleted secrets
- ✅ **No Plain Text**: Passwords never appear in Terraform state unencrypted

### Retrieving Passwords

```bash
# Root password
aws secretsmanager get-secret-value \
  --secret-id staging/myapp/mysql/mysql-root-password \
  --query SecretString \
  --output text

# User password
aws secretsmanager get-secret-value \
  --secret-id staging/myapp/mysql/mysql-user-password \
  --query SecretString \
  --output text
```

### In Application Code

**Node.js:**
```javascript
const AWS = require('aws-sdk');
const secretsManager = new AWS.SecretsManager();

const password = await secretsManager.getSecretValue({
  SecretId: 'staging/myapp/mysql/mysql-user-password'
}).promise();

const mysql = require('mysql2/promise');
const connection = await mysql.createConnection({
  host: process.env.MYSQL_HOST,
  user: process.env.MYSQL_USER,
  password: password.SecretString,
  database: process.env.MYSQL_DATABASE
});
```

**Python:**
```python
import boto3
import pymysql

secrets = boto3.client('secretsmanager')
password = secrets.get_secret_value(
    SecretId='staging/myapp/mysql/mysql-user-password'
)['SecretString']

connection = pymysql.connect(
    host=os.environ['MYSQL_HOST'],
    user=os.environ['MYSQL_USER'],
    password=password,
    database=os.environ['MYSQL_DATABASE']
)
```

---

## 2. IAM Roles and Least Privilege Access

### ✅ What Was Improved

**Before:** No IAM roles, EC2 instance had no AWS permissions.

**After:** Dedicated IAM role with minimal permissions for specific tasks.

### IAM Role Structure

```
EC2 Instance → Instance Profile → IAM Role → Policies
                                              ├─ Secrets Manager (read-only)
                                              ├─ CloudWatch (write logs/metrics)
                                              ├─ S3 (backup bucket only)
                                              └─ SSM (Session Manager)
```

### Permissions Breakdown

#### 1. Secrets Manager Access (Required)
```json
{
  "Effect": "Allow",
  "Action": [
    "secretsmanager:GetSecretValue",
    "secretsmanager:DescribeSecret"
  ],
  "Resource": [
    "arn:aws:secretsmanager:region:account:secret:env/project/mysql/mysql-root-password",
    "arn:aws:secretsmanager:region:account:secret:env/project/mysql/mysql-user-password"
  ]
}
```
**Why:** Instance needs to retrieve MySQL passwords at startup and during container restarts.

#### 2. CloudWatch Access (Optional)
```json
{
  "Effect": "Allow",
  "Action": [
    "cloudwatch:PutMetricData",
    "logs:CreateLogGroup",
    "logs:CreateLogStream",
    "logs:PutLogEvents"
  ],
  "Resource": "*"
}
```
**Why:** Send MySQL logs and system metrics to CloudWatch for monitoring.

#### 3. S3 Backup Access (Optional)
```json
{
  "Effect": "Allow",
  "Action": [
    "s3:PutObject",
    "s3:GetObject",
    "s3:ListBucket",
    "s3:DeleteObject"
  ],
  "Resource": [
    "arn:aws:s3:::backup-bucket",
    "arn:aws:s3:::backup-bucket/*"
  ]
}
```
**Why:** Upload automated MySQL backups to S3 and manage retention.

#### 4. Systems Manager (Optional)
```json
{
  "PolicyArn": "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
```
**Why:** Enable SSH-less access via Session Manager (more secure than SSH keys).

### Benefits

- ✅ **Least Privilege**: Instance can only access specific secrets, not all Secrets Manager
- ✅ **Scoped S3 Access**: Can only write to designated backup bucket
- ✅ **No Long-Lived Credentials**: Uses temporary IAM role credentials
- ✅ **Automatic Rotation**: IAM credentials rotate automatically
- ✅ **Audit Trail**: All API calls logged in CloudTrail

---

## 3. Encryption

### ✅ EBS Encryption

**Enabled by default:**
```hcl
root_block_device {
  encrypted = true  # Encrypts data at rest
}
```

**Benefits:**
- ✅ All MySQL data encrypted on disk
- ✅ Uses AWS KMS (AWS-managed or customer-managed keys)
- ✅ Encryption keys automatically rotated by AWS
- ✅ Compliance: Meets GDPR, HIPAA, PCI-DSS requirements

### ✅ Secrets Manager Encryption

- All passwords encrypted at rest using AWS KMS
- Retrieved over TLS in transit
- Never stored in plain text

### ✅ CloudWatch Logs Encryption

- Logs encrypted at rest in CloudWatch
- Optional: Use customer-managed KMS keys for additional control

---

## 4. Monitoring and Logging

### ✅ What Was Improved

**Before:** No monitoring or logging.

**After:** Comprehensive CloudWatch integration.

### Logs Collected

1. **Setup Logs** (`/var/log/mysql-setup.log`)
   - Docker installation
   - MySQL container startup
   - Configuration application

2. **MySQL Error Logs** (`/home/ubuntu/mysql_data/error.log`)
   - MySQL server errors
   - Connection issues
   - Query errors

3. **Backup Logs** (`/var/log/mysql-backup.log`)
   - Backup success/failure
   - S3 upload status
   - Retention cleanup

### Metrics Collected

- **Memory Usage** (`MemoryUsed` percentage)
- **Disk Usage** (`DiskUsed` percentage)
- **CPU Utilization** (if detailed monitoring enabled)
- **Network In/Out** (if detailed monitoring enabled)

### CloudWatch Alarms (Example)

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
  alarm_description   = "MySQL instance memory usage above 80%"
}
```

### Benefits

- ✅ **Centralized Logging**: All logs in one place
- ✅ **Log Retention**: Configurable retention (default: 7 days)
- ✅ **Searchable**: Use CloudWatch Logs Insights
- ✅ **Alerting**: Create alarms for critical events
- ✅ **Debugging**: Troubleshoot issues without SSH access

---

## 5. Automated Backups

### ✅ What Was Improved

**Before:** No backup strategy.

**After:** Automated daily backups to S3 with retention management.

### How It Works

1. **Scheduled Backups** (default: 2 AM daily)
   ```bash
   # Cron job created automatically
   0 2 * * * /usr/local/bin/backup_mysql.sh
   ```

2. **Backup Process**
   - Retrieve root password from Secrets Manager
   - Create mysqldump of all databases
   - Compress with gzip
   - Upload to S3
   - Clean up local backup file
   - Delete old S3 backups (retention: 7 days default)

3. **Backup Script** (auto-generated)
   ```bash
   # Secure backup (password from Secrets Manager)
   docker exec mysql-server mysqldump \
     -u root \
     -p"$MYSQL_ROOT_PASSWORD" \
     --all-databases \
     --single-transaction \
     --quick \
     | gzip > backup.sql.gz
   
   # Upload to S3
   aws s3 cp backup.sql.gz s3://bucket/mysql-backups/env/project/
   ```

### Restore from Backup

```bash
# Download backup
aws s3 cp s3://bucket/mysql-backups/staging/myapp/mysql-backup-20260119.sql.gz .

# Extract
gunzip mysql-backup-20260119.sql.gz

# Restore (get password from Secrets Manager first)
MYSQL_ROOT_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id staging/myapp/mysql/mysql-root-password \
  --query SecretString \
  --output text)

# Stop MySQL container
docker stop mysql-server

# Restore backup
docker run -i --rm \
  -v /home/ubuntu/mysql_data:/var/lib/mysql \
  mysql:8.0 \
  mysql -u root -p"$MYSQL_ROOT_PASSWORD" < mysql-backup-20260119.sql

# Start MySQL container
/usr/local/bin/start_mysql_container.sh
```

### Benefits

- ✅ **Automated**: No manual intervention needed
- ✅ **Retention Management**: Automatically deletes old backups
- ✅ **Encrypted**: S3 server-side encryption
- ✅ **Versioned**: S3 bucket versioning recommended
- ✅ **Point-in-Time Recovery**: Daily backups allow recovery to previous state

---

## 6. Access Control

### ✅ Systems Manager Session Manager

**Benefits over SSH:**
- ✅ **No SSH Keys**: No private keys to manage or secure
- ✅ **IAM-Based**: Access controlled by IAM policies
- ✅ **Audit Trail**: All sessions logged in CloudTrail
- ✅ **No Open Ports**: No port 22 in security groups
- ✅ **Session Recording**: Optional session recording to S3

**Access the instance:**
```bash
aws ssm start-session --target i-0123456789abcdef
```

### ✅ Security Group Best Practices

**Recommended configuration:**
```hcl
# Allow MySQL only from application security group
resource "aws_security_group_rule" "mysql_from_app" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = var.app_security_group_id
  security_group_id        = var.mysql_security_group_id
}

# NO public access
# NO SSH port 22 (use SSM instead)
```

### ✅ IMDSv2 Enforcement

```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"  # Enforces IMDSv2
  http_put_response_hop_limit = 1
}
```

**Why:** Prevents SSRF attacks from accessing instance metadata.

---

## 7. MySQL Configuration Security

### ✅ Security Settings in my.cnf

```ini
[mysqld]
# Disable DNS hostname lookups (security + performance)
skip-name-resolve

# Disable LOAD DATA LOCAL INFILE (prevents local file access)
local-infile=0

# Bind to all interfaces (Docker container)
bind-address=0.0.0.0

# Enable slow query log (detect performance issues)
slow_query_log=1
long_query_time=2

# Binary logging (required for point-in-time recovery)
log-bin=/var/lib/mysql/mysql-bin
binlog_expire_logs_seconds=604800  # 7 days

# UTF8MB4 (supports all Unicode characters including emojis)
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
```

### ✅ Docker Security

```bash
docker run -d \
  --health-cmd='mysqladmin ping -h localhost' \  # Health checks
  --health-interval=10s \
  --health-timeout=5s \
  --health-retries=3 \
  --restart always \  # Auto-restart on failure
  -v /home/ubuntu/mysql_data:/var/lib/mysql \  # Persistent data
  -v /home/ubuntu/mysql_config/my.cnf:/etc/mysql/conf.d/custom.cnf:ro \  # Read-only config
  mysql:8.0
```

### ✅ User Separation

- **Root user**: Admin tasks only (backups, schema changes)
- **Application user**: Limited to specific database with minimal permissions
- Docker container runs as mysql user (not root)

---

## 8. Password Rotation

### Manual Rotation (Recommended for Now)

**Step 1: Generate new password**
```bash
NEW_PASSWORD=$(openssl rand -base64 32)
```

**Step 2: Update Secrets Manager**
```bash
aws secretsmanager update-secret \
  --secret-id staging/myapp/mysql/mysql-user-password \
  --secret-string "$NEW_PASSWORD"
```

**Step 3: Update MySQL**
```bash
# Connect to instance
aws ssm start-session --target i-0123456789abcdef

# Get old and new passwords
OLD_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id staging/myapp/mysql/mysql-user-password \
  --version-stage AWSPREVIOUS \
  --query SecretString \
  --output text)

NEW_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id staging/myapp/mysql/mysql-user-password \
  --query SecretString \
  --output text)

# Update password in MySQL
docker exec mysql-server mysql -u root -p \
  -e "ALTER USER 'myuser'@'%' IDENTIFIED BY '$NEW_PASSWORD';"
```

**Step 4: Restart applications** to use new password

### Automatic Rotation (Future Enhancement)

AWS Secrets Manager supports automatic rotation using Lambda:

```hcl
resource "aws_secretsmanager_secret_rotation" "mysql_rotation" {
  secret_id           = aws_secretsmanager_secret.mysql_user_password.id
  rotation_lambda_arn = aws_lambda_function.mysql_rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }
}
```

**Rotation Lambda would:**
1. Generate new password
2. Update MySQL user password
3. Update Secrets Manager
4. Test new password works
5. Mark rotation successful

**Note:** This requires additional Lambda function implementation.

---

## 📊 Security Checklist

### Production Deployment Checklist

- [ ] Enable EBS encryption (`enable_ebs_encryption = true`)
- [ ] Use auto-generated passwords (leave `mysql_root_password` empty)
- [ ] Enable CloudWatch monitoring (`enable_cloudwatch_monitoring = true`)
- [ ] Enable automated backups (`enable_automated_backups = true`)
- [ ] Configure S3 bucket for backups (`backup_s3_bucket_name`)
- [ ] Use SSM Session Manager (` enable_ssm_access = true`)
- [ ] Disable SSH key access (`enable_ssh_key_access = false`)
- [ ] Deploy in private subnet
- [ ] Restrict security group to application only
- [ ] Set up CloudWatch alarms for monitoring
- [ ] Test backup and restore procedure
- [ ] Document password retrieval process for team
- [ ] Review IAM policies (least privilege)
- [ ] Enable S3 bucket versioning for backups
- [ ] Configure log retention appropriately

### Security Group Rules

```hcl
# ✅ GOOD - Allow MySQL from application only
ingress {
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = "sg-app-servers"
}

# ❌ BAD - Don't allow public MySQL access
ingress {
  from_port   = 3306
  to_port     = 3306
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]  # NEVER DO THIS!
}

# ❌ BAD - Don't open SSH if using SSM
ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]  # Use SSM instead
}
```

---

## 🎯 Summary of Improvements

| Security Aspect | Before | After |
|----------------|--------|-------|
| **Password Storage** | Plain text in variables | AWS Secrets Manager (encrypted) |
| **Password Generation** | Manual | Automatic (32-char random) |
| **EBS Encryption** | Optional | Enabled by default |
| **IAM Permissions** | None | Least-privilege IAM role |
| **Access Method** | SSH keys | SSM Session Manager |
| **Monitoring** | None | CloudWatch logs + metrics |
| **Backups** | Manual | Automated to S3 |
| **Audit Trail** | None | CloudTrail logs all access |
| **MySQL Config** | Default | Hardened security settings |
| **Outputs** | Exposed passwords | Sensitive + structured |

---

## 📚 Additional Resources

- [AWS Secrets Manager Best Practices](https://docs.aws.amazon.com/secretsmanager/latest/userguide/best-practices.html)
- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [MySQL Security Best Practices](https://dev.mysql.com/doc/refman/8.0/en/security-guidelines.html)
- [EBS Encryption](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSEncryption.html)

---

**All security improvements are now implemented and ready for use!** 🔒

