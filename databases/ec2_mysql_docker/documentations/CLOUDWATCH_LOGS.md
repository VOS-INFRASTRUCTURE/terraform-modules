# CloudWatch Logs Collection - System Logs

## Overview

The CloudWatch agent now collects **comprehensive system logs** in addition to MySQL-specific logs. This provides full visibility into system events, security, and troubleshooting.

---

## Logs Collected

### 1. MySQL Application Logs

| Log File | Stream Name | Purpose |
|----------|-------------|---------|
| `/var/log/mysql-setup.log` | `{instance_id}/setup.log` | EC2 instance setup and MySQL installation logs |
| `/home/ubuntu/mysql_data/error.log` | `{instance_id}/mysql-error.log` | MySQL server errors and warnings |
| `/var/log/mysql-backup.log` | `{instance_id}/backup.log` | MySQL backup script execution logs |

### 2. System Logs (NEW! ✅)

| Log File | Stream Name | Purpose |
|----------|-------------|---------|
| `/var/log/syslog` | `{instance_id}/syslog` | **System-wide logs** - all system events, services, daemons |
| `/var/log/auth.log` | `{instance_id}/auth.log` | **Authentication logs** - SSH logins, sudo usage, authentication failures |
| `/var/log/cloud-init.log` | `{instance_id}/cloud-init.log` | **Cloud-init logs** - EC2 initialization process |
| `/var/log/cloud-init-output.log` | `{instance_id}/cloud-init-output.log` | **Cloud-init output** - User data script execution |
| `/var/log/docker.log` | `{instance_id}/docker.log` | **Docker daemon logs** - Container management events |

---

## Why Collect System Logs?

### Security Monitoring

**Auth.log** shows:
- ✅ SSH login attempts (successful and failed)
- ✅ Sudo command execution
- ✅ User authentication events
- ✅ Potential brute force attacks
- ✅ Unauthorized access attempts

**Example:**
```
Jan 19 02:15:32 ip-10-0-1-50 sshd[1234]: Failed password for invalid user admin from 192.168.1.100
Jan 19 02:15:35 ip-10-0-1-50 sshd[1234]: Failed password for invalid user admin from 192.168.1.100
Jan 19 02:15:38 ip-10-0-1-50 sshd[1234]: Failed password for invalid user admin from 192.168.1.100
```
→ **Alert:** Potential brute force attack detected!

### System Troubleshooting

**Syslog** shows:
- ✅ Service start/stop events
- ✅ Kernel messages
- ✅ System errors
- ✅ Package installation logs
- ✅ Network events

**Example:**
```
Jan 19 03:00:01 ip-10-0-1-50 CRON[5678]: (root) CMD (/usr/local/bin/backup_mysql.sh)
Jan 19 03:00:15 ip-10-0-1-50 systemd[1]: docker.service: Failed with result 'exit-code'.
```
→ **Troubleshoot:** Docker service crashed during backup

### Deployment Debugging

**Cloud-init logs** show:
- ✅ User data script execution
- ✅ Package installation progress
- ✅ Configuration file creation
- ✅ Errors during instance bootstrap

**Example:**
```
Cloud-init v. 23.1.2 running 'modules:final' at Sun, 19 Jan 2026 02:00:00 +0000
Successfully installed Docker version 24.0.7
MySQL container started successfully
```

### Docker Troubleshooting

**Docker logs** show:
- ✅ Container lifecycle events
- ✅ Image pull operations
- ✅ Docker daemon errors
- ✅ Container restart events

**Example:**
```
Jan 19 03:15:22 ip-10-0-1-50 dockerd[1234]: Container mysql-server health check failed
Jan 19 03:15:25 ip-10-0-1-50 dockerd[1234]: Container mysql-server restarted
```

---

## How to View Logs in CloudWatch

### Via AWS Console

1. **Navigate to CloudWatch:**
   ```
   AWS Console → CloudWatch → Log groups → /aws/ec2/{env}-{project}-{base_name}-mysql
   ```

2. **Select log stream:**
   ```
   Log streams:
   ├── i-0123456789abcdef/syslog
   ├── i-0123456789abcdef/auth.log
   ├── i-0123456789abcdef/mysql-error.log
   ├── i-0123456789abcdef/setup.log
   ├── i-0123456789abcdef/backup.log
   ├── i-0123456789abcdef/cloud-init.log
   ├── i-0123456789abcdef/cloud-init-output.log
   └── i-0123456789abcdef/docker.log
   ```

3. **Search and filter:**
   - Use CloudWatch Logs Insights for advanced queries
   - Filter by time range
   - Search for specific error messages

### Via AWS CLI

```bash
# View syslog (live tail)
aws logs tail /aws/ec2/production-myapp-mysql-mysql \
  --log-stream-names i-0123456789abcdef/syslog \
  --follow

# View auth logs (last hour)
aws logs tail /aws/ec2/production-myapp-mysql-mysql \
  --log-stream-names i-0123456789abcdef/auth.log \
  --since 1h

# View MySQL errors
aws logs tail /aws/ec2/production-myapp-mysql-mysql \
  --log-stream-names i-0123456789abcdef/mysql-error.log \
  --follow

# View backup logs
aws logs tail /aws/ec2/production-myapp-mysql-mysql \
  --log-stream-names i-0123456789abcdef/backup.log
```

### CloudWatch Logs Insights Queries

**Find failed SSH attempts:**
```sql
fields @timestamp, @message
| filter @logStream like /auth.log/
| filter @message like /Failed password/
| sort @timestamp desc
| limit 100
```

**Find MySQL errors:**
```sql
fields @timestamp, @message
| filter @logStream like /mysql-error.log/
| filter @message like /ERROR/
| sort @timestamp desc
| limit 50
```

**Find Docker container restarts:**
```sql
fields @timestamp, @message
| filter @logStream like /docker.log/
| filter @message like /restarted/
| sort @timestamp desc
```

**Find backup failures:**
```sql
fields @timestamp, @message
| filter @logStream like /backup.log/
| filter @message like /error|failed|Error|Failed/
| sort @timestamp desc
```

---

## Create CloudWatch Alarms

### SSH Brute Force Detection

```hcl
resource "aws_cloudwatch_log_metric_filter" "ssh_brute_force" {
  name           = "ssh-brute-force-attempts"
  log_group_name = "/aws/ec2/production-myapp-mysql-mysql"
  pattern        = "[time, host, process, ...] Failed password"

  metric_transformation {
    name      = "SSHFailedLoginAttempts"
    namespace = "MySQL/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "ssh_brute_force_alarm" {
  alarm_name          = "mysql-ssh-brute-force"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SSHFailedLoginAttempts"
  namespace           = "MySQL/Security"
  period              = 300  # 5 minutes
  statistic           = "Sum"
  threshold           = 5  # More than 5 failed attempts in 5 minutes
  alarm_description   = "SSH brute force attack detected on MySQL server"
  
  alarm_actions = [var.sns_topic_arn]
}
```

### MySQL Error Detection

```hcl
resource "aws_cloudwatch_log_metric_filter" "mysql_errors" {
  name           = "mysql-errors"
  log_group_name = "/aws/ec2/production-myapp-mysql-mysql"
  pattern        = "[ERROR]"

  metric_transformation {
    name      = "MySQLErrors"
    namespace = "MySQL/Application"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "mysql_errors_alarm" {
  alarm_name          = "mysql-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MySQLErrors"
  namespace           = "MySQL/Application"
  period              = 300
  statistic           = "Sum"
  threshold           = 10  # More than 10 errors in 10 minutes
  
  alarm_actions = [var.sns_topic_arn]
}
```

### Backup Failure Detection

```hcl
resource "aws_cloudwatch_log_metric_filter" "backup_failures" {
  name           = "mysql-backup-failures"
  log_group_name = "/aws/ec2/production-myapp-mysql-mysql"
  pattern        = "[time, msg*=*failed* || msg*=*error*]"

  metric_transformation {
    name      = "MySQLBackupFailures"
    namespace = "MySQL/Backup"
    value     = "1"
  }
}
```

---

## Log Retention and Costs

**Default retention:** 7 days (configurable via `log_retention_days` variable)

**Cost estimate:**
- CloudWatch Logs ingestion: $0.50/GB
- CloudWatch Logs storage: $0.03/GB/month

**Typical usage:**
- System logs: ~100-500 MB/month
- MySQL logs: ~50-200 MB/month
- **Total cost:** $0.50-1.00/month

**To reduce costs:**
```hcl
module "mysql" {
  # ... other config ...
  log_retention_days = 3  # Reduce from default 7 days
}
```

---

## Troubleshooting Common Issues

### Logs not appearing in CloudWatch

**Check:**
1. CloudWatch agent is running:
   ```bash
   sudo systemctl status amazon-cloudwatch-agent
   ```

2. CloudWatch agent configuration:
   ```bash
   cat /opt/aws/amazon-cloudwatch-agent/etc/config.json
   ```

3. IAM role has CloudWatch permissions:
   ```bash
   aws iam get-role-policy --role-name {role-name} --policy-name cloudwatch-access
   ```

### Log files don't exist

Some logs may not exist until events occur:
- `/var/log/mysql-backup.log` - created after first backup
- `/var/log/docker.log` - may be `/var/log/docker.log` or journalctl
- `/home/ubuntu/mysql_data/error.log` - created by MySQL container

### High CloudWatch costs

**Solutions:**
1. Reduce retention period
2. Filter verbose logs
3. Use log sampling for high-volume streams

---

## Summary

**Before:** Only MySQL application logs ❌  
**After:** Complete system visibility ✅

**New logs added:**
- ✅ System logs (syslog)
- ✅ Authentication logs (auth.log)
- ✅ Cloud-init logs
- ✅ Docker logs
- ✅ Backup logs

**Benefits:**
- 🔒 Security monitoring (detect intrusions)
- 🐛 Better debugging (system-wide events)
- 📊 Complete audit trail
- ⚠️ Proactive alerting (errors before failures)

**The CloudWatch logging is now comprehensive and production-ready!** 📊

