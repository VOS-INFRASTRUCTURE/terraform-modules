# Redis CloudWatch Logs - Complete System Monitoring

## Overview

The CloudWatch agent collects **comprehensive system logs** in addition to Redis-specific logs, providing full visibility into Redis operations, system events, and security.

---

## Logs Collected

### Redis Application Logs

| Log File | Stream Name | Purpose |
|----------|-------------|---------|
| `/var/log/redis/redis-server.log` | `{instance_id}/redis.log` | Redis server logs, connections, commands |
| `/var/log/redis-setup.log` | `{instance_id}/setup.log` | EC2 instance setup and Redis installation |
| `/var/log/redis-backup.log` | `{instance_id}/backup.log` | Redis backup execution logs |

### System Logs (Complete Visibility)

| Log File | Stream Name | Purpose |
|----------|-------------|---------|
| `/var/log/syslog` | `{instance_id}/syslog` | **System-wide events** - all services, daemons |
| `/var/log/auth.log` | `{instance_id}/auth.log` | **Authentication** - SSH logins, sudo usage |
| `/var/log/cloud-init.log` | `{instance_id}/cloud-init.log` | **EC2 initialization** - cloud-init process |
| `/var/log/cloud-init-output.log` | `{instance_id}/cloud-init-output.log` | **User data output** - bootstrap script |

---

## Benefits

### 🔒 Security Monitoring

**Auth.log tracks:**
- SSH login attempts (successful and failed)
- Sudo command execution
- Brute force attack detection
- Unauthorized access attempts

**Example - Detect SSH brute force:**
```bash
aws logs tail /aws/ec2/production-myapp-redis \
  --log-stream-names i-xxx/auth.log \
  --filter-pattern "Failed password" \
  --follow
```

### 🐛 System Troubleshooting

**Syslog shows:**
- Service start/stop events
- System errors and warnings
- Cron job execution
- Network events

**Example - Find system errors:**
```bash
aws logs tail /aws/ec2/production-myapp-redis \
  --log-stream-names i-xxx/syslog \
  --filter-pattern "error|ERROR|failed|FAILED"
```

### 📊 Redis Monitoring

**Redis logs show:**
- Client connections/disconnections
- Command execution
- Memory warnings
- Slow queries
- AOF/RDB save operations

**Example - Monitor Redis activity:**
```bash
aws logs tail /aws/ec2/production-myapp-redis \
  --log-stream-names i-xxx/redis.log \
  --follow
```

### 🚀 Deployment Debugging

**Cloud-init logs help debug:**
- User data script execution
- Package installation
- Configuration errors
- Bootstrap failures

**Example - Debug setup issues:**
```bash
aws logs tail /aws/ec2/production-myapp-redis \
  --log-stream-names i-xxx/cloud-init-output.log
```

---

## CloudWatch Logs Insights Queries

### Find Failed SSH Attempts

```sql
fields @timestamp, @message
| filter @logStream like /auth.log/
| filter @message like /Failed password/
| sort @timestamp desc
| limit 100
```

### Find Redis Errors

```sql
fields @timestamp, @message
| filter @logStream like /redis.log/
| filter @message like /ERROR/
| sort @timestamp desc
| limit 50
```

### Find Slow Redis Commands

```sql
fields @timestamp, @message
| filter @logStream like /redis.log/
| filter @message like /slow command/
| sort @timestamp desc
```

### Monitor Backup Status

```sql
fields @timestamp, @message
| filter @logStream like /backup.log/
| filter @message like /completed|failed|error/
| sort @timestamp desc
```

### Find System Errors

```sql
fields @timestamp, @message
| filter @logStream like /syslog/
| filter @message like /error|ERROR|fail|FAIL/
| sort @timestamp desc
```

---

## Create CloudWatch Alarms

### SSH Brute Force Detection

```hcl
resource "aws_cloudwatch_log_metric_filter" "redis_ssh_brute_force" {
  name           = "redis-ssh-brute-force"
  log_group_name = aws_cloudwatch_log_group.redis[0].name
  pattern        = "[time, host, process, ...] Failed password"

  metric_transformation {
    name      = "RedisSSHFailedAttempts"
    namespace = "Redis/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "redis_ssh_alarm" {
  alarm_name          = "redis-ssh-brute-force-detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RedisSSHFailedAttempts"
  namespace           = "Redis/Security"
  period              = 300  # 5 minutes
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "SSH brute force detected on Redis server"
}
```

### Redis Error Rate Alarm

```hcl
resource "aws_cloudwatch_log_metric_filter" "redis_errors" {
  name           = "redis-errors"
  log_group_name = aws_cloudwatch_log_group.redis[0].name
  pattern        = "[ERROR]"

  metric_transformation {
    name      = "RedisErrors"
    namespace = "Redis/Application"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "redis_error_alarm" {
  alarm_name          = "redis-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RedisErrors"
  namespace           = "Redis/Application"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
}
```

### Backup Failure Detection

```hcl
resource "aws_cloudwatch_log_metric_filter" "redis_backup_failures" {
  name           = "redis-backup-failures"
  log_group_name = aws_cloudwatch_log_group.redis[0].name
  pattern        = "[time, msg*=*failed* || msg*=*error*]"

  metric_transformation {
    name      = "RedisBackupFailures"
    namespace = "Redis/Backup"
    value     = "1"
  }
}
```

---

## Viewing Logs

### Via AWS CLI

```bash
# Redis logs (live tail)
aws logs tail /aws/ec2/production-myapp-redis \
  --log-stream-names i-xxx/redis.log \
  --follow

# Authentication logs
aws logs tail /aws/ec2/production-myapp-redis \
  --log-stream-names i-xxx/auth.log \
  --since 1h

# System logs
aws logs tail /aws/ec2/production-myapp-redis \
  --log-stream-names i-xxx/syslog \
  --follow

# Backup logs
aws logs tail /aws/ec2/production-myapp-redis \
  --log-stream-names i-xxx/backup.log

# Setup logs (debug installation issues)
aws logs tail /aws/ec2/production-myapp-redis \
  --log-stream-names i-xxx/setup.log
```

### Via AWS Console

1. Navigate to **CloudWatch → Log groups**
2. Select: `/aws/ec2/{env}-{project}-redis`
3. Choose log stream:
   - `i-xxx/redis.log` - Redis server logs
   - `i-xxx/syslog` - System logs
   - `i-xxx/auth.log` - Authentication
   - `i-xxx/setup.log` - Installation
   - `i-xxx/backup.log` - Backups
   - `i-xxx/cloud-init.log` - Bootstrap
   - `i-xxx/cloud-init-output.log` - User data output

---

## Common Use Cases

### Debug Redis Not Starting

```bash
# Check setup logs
aws logs tail /aws/ec2/production-myapp-redis \
  --log-stream-names i-xxx/setup.log

# Check system logs
aws logs tail /aws/ec2/production-myapp-redis \
  --log-stream-names i-xxx/syslog \
  --filter-pattern "redis"

# Check Redis logs
aws logs tail /aws/ec2/production-myapp-redis \
  --log-stream-names i-xxx/redis.log
```

### Investigate Connection Issues

```bash
# Check Redis logs for connection errors
aws logs tail /aws/ec2/production-myapp-redis \
  --log-stream-names i-xxx/redis.log \
  --filter-pattern "Connection|refused|timeout"

# Check if Redis is accepting connections
aws logs tail /aws/ec2/production-myapp-redis \
  --log-stream-names i-xxx/redis.log \
  --filter-pattern "Accepted"
```

### Monitor Memory Usage

```bash
# Check Redis memory warnings
aws logs tail /aws/ec2/production-myapp-redis \
  --log-stream-names i-xxx/redis.log \
  --filter-pattern "memory"
```

### Verify Backups

```bash
# Check backup completion
aws logs tail /aws/ec2/production-myapp-redis \
  --log-stream-names i-xxx/backup.log \
  --filter-pattern "completed|Backup completed"
```

---

## Log Retention and Costs

**Default retention:** 7 days (configurable via `log_retention_days`)

**Cost estimate:**
- CloudWatch Logs ingestion: $0.50/GB
- CloudWatch Logs storage: $0.03/GB/month
- Typical usage: ~50-200 MB/month
- **Estimated cost:** $0.25-0.50/month

**To reduce costs:**
```hcl
module "redis" {
  # ... other config ...
  log_retention_days = 3  # Reduce from 7 days
}
```

---

## Troubleshooting

### Logs not appearing in CloudWatch

**Check CloudWatch agent status:**
```bash
# Connect via SSM
aws ssm start-session --target i-xxx

# Check agent status
sudo systemctl status amazon-cloudwatch-agent

# Check agent config
cat /opt/aws/amazon-cloudwatch-agent/etc/cloudwatch-config.json

# Restart agent
sudo systemctl restart amazon-cloudwatch-agent
```

### Log files don't exist

Some logs created only after events:
- `/var/log/redis-backup.log` - after first backup runs
- `/var/log/redis/redis-server.log` - after Redis starts

**Check if files exist:**
```bash
ls -la /var/log/redis/
ls -la /var/log/redis-*.log
```

---

## Summary

**Logs collected:**
- ✅ Redis server logs (connections, commands, errors)
- ✅ Redis setup logs (installation, configuration)
- ✅ Redis backup logs (backup execution)
- ✅ System logs (syslog - all system events)
- ✅ Authentication logs (SSH, sudo)
- ✅ Cloud-init logs (EC2 bootstrap)

**Benefits:**
- 🔒 Complete security visibility
- 🐛 Better troubleshooting
- 📊 Full audit trail
- ⚠️ Proactive alerting

**Redis CloudWatch logging is now comprehensive and production-ready!** 📊

