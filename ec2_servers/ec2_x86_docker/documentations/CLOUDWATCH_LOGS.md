# CloudWatch Logs Collection - Docker EC2 Server

## Overview

The CloudWatch agent collects **comprehensive system and Docker logs** for monitoring, troubleshooting, and security auditing.

---

## Logs Collected

### System Logs

| Log File | Stream Name | Purpose |
|----------|-------------|---------|
| `/var/log/server-setup.log` | `{instance_id}/setup.log` | EC2 instance setup and configuration logs |
| `/var/log/syslog` | `{instance_id}/syslog` | **System-wide logs** - all system events, services, daemons |
| `/var/log/auth.log` | `{instance_id}/auth.log` | **Authentication logs** - login attempts, sudo usage, authentication failures |
| `/var/log/cloud-init.log` | `{instance_id}/cloud-init.log` | **Cloud-init logs** - EC2 initialization process |
| `/var/log/cloud-init-output.log` | `{instance_id}/cloud-init-output.log` | **Cloud-init output** - User data script execution |
| `/var/log/docker.log` | `{instance_id}/docker.log` | **Docker daemon logs** - Container management events (if Docker logging configured) |

---

## Why Collect These Logs?

### 1. Security Monitoring

**Auth.log** provides visibility into:
- ✅ SSM Session Manager connections
- ✅ Sudo command execution
- ✅ User authentication events
- ✅ Unauthorized access attempts

**Example - Suspicious Activity Detection:**
```
Jan 19 02:15:32 ip-10-0-1-50 sudo: ubuntu : TTY=pts/0 ; PWD=/home/ubuntu ; USER=root ; COMMAND=/bin/bash
Jan 19 02:15:35 ip-10-0-1-50 sudo: ubuntu : TTY=pts/0 ; PWD=/root ; USER=root ; COMMAND=/usr/bin/cat /etc/shadow
```
→ **Alert:** Unusual privilege escalation detected!

### 2. System Troubleshooting

**Syslog** shows:
- ✅ Service start/stop events
- ✅ Kernel messages and system errors
- ✅ Package installation logs
- ✅ Network events
- ✅ Cron job execution

**Example - Service Failure:**
```
Jan 19 03:00:01 ip-10-0-1-50 systemd[1]: docker.service: Failed with result 'exit-code'.
Jan 19 03:00:02 ip-10-0-1-50 systemd[1]: docker.service: Start request repeated too quickly.
```
→ **Troubleshoot:** Docker service crashed, check logs for root cause

### 3. Deployment Debugging

**Cloud-init logs** capture:
- ✅ User data script execution
- ✅ Package installation progress
- ✅ Configuration file creation
- ✅ Errors during instance bootstrap

**Example - Successful Deployment:**
```
Cloud-init v. 23.1.2 running 'modules:final' at Sun, 19 Jan 2026 02:00:00 +0000
Installing Docker...
Successfully installed Docker version 24.0.7
CloudWatch agent configured and started
Instance setup completed successfully
```

### 4. Docker Container Monitoring

**Docker logs** reveal:
- ✅ Container lifecycle events
- ✅ Image pull operations
- ✅ Docker daemon errors
- ✅ Container restart events
- ✅ Resource allocation issues

**Example - Container Issues:**
```
Jan 19 03:15:22 ip-10-0-1-50 dockerd[1234]: Container app-server OOMKilled
Jan 19 03:15:25 ip-10-0-1-50 dockerd[1234]: Container app-server restarted (restart policy: always)
```
→ **Action:** Container ran out of memory, increase memory limits

---

## How to View Logs in CloudWatch

### Via AWS Console

1. **Navigate to CloudWatch:**
   - AWS Console → CloudWatch → Log groups
   - Find your log group: `/aws/ec2/{project}-{env}-{base_name}`

2. **Select log stream:**
   - Each EC2 instance has its own streams identified by `{instance_id}`
   - Example streams:
     - `i-0a1b2c3d4e5f/setup.log`
     - `i-0a1b2c3d4e5f/syslog`
     - `i-0a1b2c3d4e5f/auth.log`

3. **View logs:**
   - Click on stream name
   - Use time range selector to filter
   - Use search box to filter by keyword

### Via AWS CLI

#### View Recent Logs (Live Tail)

```bash
# Get project and environment from Terraform
PROJECT=$(terraform output -json docker_server | jq -r '.project_id')
ENV=$(terraform output -json docker_server | jq -r '.environment')
INSTANCE_ID=$(terraform output -json docker_server | jq -r '.instance.id')

# Tail setup logs
aws logs tail "/aws/ec2/${PROJECT}-${ENV}-{base_name}/setup.log" --follow

# Tail system logs
aws logs tail "/aws/ec2/${PROJECT}-${ENV}-{base_name}/syslog" --follow

# Tail auth logs (security events)
aws logs tail "/aws/ec2/${PROJECT}-${ENV}-{base_name}/auth.log" --follow
```

#### Search Logs for Specific Events

```bash
# Search for errors in setup logs
aws logs filter-log-events \
  --log-group-name "/aws/ec2/${PROJECT}-${ENV}-{base_name}" \
  --log-stream-name-prefix "${INSTANCE_ID}/setup" \
  --filter-pattern "ERROR"

# Search for failed authentication attempts
aws logs filter-log-events \
  --log-group-name "/aws/ec2/${PROJECT}-${ENV}-{base_name}" \
  --log-stream-name-prefix "${INSTANCE_ID}/auth" \
  --filter-pattern "Failed password"

# Search for Docker errors
aws logs filter-log-events \
  --log-group-name "/aws/ec2/${PROJECT}-${ENV}-{base_name}" \
  --log-stream-name-prefix "${INSTANCE_ID}/syslog" \
  --filter-pattern "docker"
```

#### Download Logs for Analysis

```bash
# Download last hour of syslog
aws logs get-log-events \
  --log-group-name "/aws/ec2/${PROJECT}-${ENV}-{base_name}" \
  --log-stream-name "${INSTANCE_ID}/syslog" \
  --start-time $(date -u -d '1 hour ago' +%s)000 \
  --output json > syslog-$(date +%Y%m%d-%H%M).json

# Download auth logs from last 24 hours
aws logs get-log-events \
  --log-group-name "/aws/ec2/${PROJECT}-${ENV}-{base_name}" \
  --log-stream-name "${INSTANCE_ID}/auth.log" \
  --start-time $(date -u -d '24 hours ago' +%s)000 \
  --output json > auth-$(date +%Y%m%d).json
```

---

## Common Log Analysis Patterns

### 1. Find Failed Deployments

```bash
aws logs filter-log-events \
  --log-group-name "/aws/ec2/${PROJECT}-${ENV}-{base_name}" \
  --log-stream-name-prefix "${INSTANCE_ID}/cloud-init" \
  --filter-pattern "error" \
  --start-time $(date -u -d '1 hour ago' +%s)000
```

### 2. Monitor Sudo Usage

```bash
aws logs filter-log-events \
  --log-group-name "/aws/ec2/${PROJECT}-${ENV}-{base_name}" \
  --log-stream-name-prefix "${INSTANCE_ID}/auth" \
  --filter-pattern "sudo" \
  --start-time $(date -u -d '24 hours ago' +%s)000
```

### 3. Track Container Restarts

```bash
aws logs filter-log-events \
  --log-group-name "/aws/ec2/${PROJECT}-${ENV}-{base_name}" \
  --log-stream-name-prefix "${INSTANCE_ID}/syslog" \
  --filter-pattern "docker" \
  --start-time $(date -u -d '1 hour ago' +%s)000
```

### 4. Find System Errors

```bash
aws logs filter-log-events \
  --log-group-name "/aws/ec2/${PROJECT}-${ENV}-{base_name}" \
  --log-stream-name-prefix "${INSTANCE_ID}/syslog" \
  --filter-pattern "?ERROR ?CRITICAL ?FATAL" \
  --start-time $(date -u -d '6 hours ago' +%s)000
```

---

## Setting Up CloudWatch Alarms

### Example: Alert on Authentication Failures

```hcl
resource "aws_cloudwatch_log_metric_filter" "failed_auth" {
  name           = "${var.project_id}-${var.env}-failed-auth"
  log_group_name = aws_cloudwatch_log_group.mysql_logs[0].name
  pattern        = "[Mon, day, timestamp, ip, id, msg1=\"Failed\", msg2=\"password\", ...]"

  metric_transformation {
    name      = "FailedAuthCount"
    namespace = "CustomSecurity"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "multiple_failed_auth" {
  alarm_name          = "${var.project_id}-${var.env}-brute-force-alert"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedAuthCount"
  namespace           = "CustomSecurity"
  period              = 300  # 5 minutes
  statistic           = "Sum"
  threshold           = 5    # Alert if 5+ failed attempts in 5 minutes
  alarm_description   = "Alert on potential brute force attack"
  
  alarm_actions = [aws_sns_topic.security_alerts.arn]
}
```

### Example: Alert on Docker Service Failures

```hcl
resource "aws_cloudwatch_log_metric_filter" "docker_failure" {
  name           = "${var.project_id}-${var.env}-docker-failure"
  log_group_name = aws_cloudwatch_log_group.mysql_logs[0].name
  pattern        = "[timestamp, host, process, ...msg=\"docker.service: Failed\"]"

  metric_transformation {
    name      = "DockerFailureCount"
    namespace = "CustomSystem"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "docker_service_down" {
  alarm_name          = "${var.project_id}-${var.env}-docker-down"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DockerFailureCount"
  namespace           = "CustomSystem"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alert when Docker service fails"
  
  alarm_actions = [aws_sns_topic.ops_alerts.arn]
}
```

---

## Log Retention and Costs

### Default Configuration

- **Retention**: 7 days (configurable via `log_retention_days`)
- **Cost**: ~$0.50 per GB ingested + $0.03 per GB stored

### Recommended Retention Periods

| Environment | Retention | Reasoning |
|-------------|-----------|-----------|
| Development | 7 days | Cost optimization |
| Staging | 14 days | Moderate debugging needs |
| Production | 30-90 days | Compliance and audit requirements |

### Cost Optimization

```hcl
module "docker_dev" {
  source = "../../ec2_servers/ec2_x86_docker"
  
  log_retention_days = 7  # Reduce costs for non-production
}

module "docker_prod" {
  source = "../../ec2_servers/ec2_x86_docker"
  
  log_retention_days = 90  # Compliance requirement
}
```

### Export Logs to S3 (Long-term Storage)

For compliance or long-term retention:

```bash
# Create S3 export task (much cheaper than CloudWatch Logs)
aws logs create-export-task \
  --log-group-name "/aws/ec2/${PROJECT}-${ENV}-{base_name}" \
  --from $(date -u -d '30 days ago' +%s)000 \
  --to $(date -u +%s)000 \
  --destination s3-bucket-name \
  --destination-prefix cloudwatch-logs/
```

---

## Troubleshooting CloudWatch Agent

### Verify Agent is Running

```bash
# Connect to instance
aws ssm start-session --target i-xxx

# Check agent status
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a query \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

# Check agent logs
tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
```

### Restart CloudWatch Agent

```bash
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json
```

---

## Best Practices

1. **Enable CloudWatch monitoring in production** (`enable_cloudwatch_monitoring = true`)
2. **Set appropriate retention periods** (balance cost vs. compliance needs)
3. **Create metric filters and alarms** for critical events
4. **Regularly review logs** for security and performance issues
5. **Export old logs to S3** for cost-effective long-term storage
6. **Use CloudWatch Insights** for advanced log analysis
7. **Set up SNS alerts** for critical log patterns

---

**Comprehensive logging enables proactive monitoring and fast incident response!** 📊

