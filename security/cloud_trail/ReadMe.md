# AWS CloudTrail Terraform Module

Terraform module to enable and configure AWS CloudTrail for comprehensive audit logging and security monitoring of AWS API calls.

## Overview

AWS CloudTrail continuously monitors and records AWS API calls and related events, enabling:

- **Security Analysis**: Detect unauthorized access attempts and security incidents
- **Compliance**: Meet regulatory requirements (SOC 2, PCI-DSS, HIPAA, GDPR)
- **Operational Troubleshooting**: Debug service issues by reviewing API call history
- **Risk Auditing**: Identify risky configurations and policy changes
- **Change Tracking**: Monitor who changed what and when
- **Forensic Investigation**: Analyze security incidents with detailed event history

## Module Structure

```
cloud_trail/
├── main.tf       # CloudWatch Log Group, IAM Role/Policy, CloudTrail Trail
├── bucket.tf     # S3 bucket configuration for CloudTrail logs
├── variables.tf  # Input variables
├── outputs.tf    # Module outputs (single 'cloudtrail' object)
└── README.md     # This file
```

## Features

✅ **Multi-Region Trail**: Captures events from ALL AWS regions automatically  
✅ **Global Service Events**: Includes IAM, Route53, CloudFront, etc.  
✅ **Log File Validation**: Cryptographic hashing to detect tampering  
✅ **Dual Delivery**: S3 (long-term storage) + CloudWatch Logs (real-time alerts)  
✅ **Encryption**: Server-side encryption (AES256)  
✅ **Versioning**: S3 versioning enabled for audit trail protection  
✅ **Lifecycle Policy**: Automatic log retention management  

## Prerequisites

- AWS account with appropriate permissions
- S3 bucket permissions (handled by this module)
- CloudWatch Logs permissions (handled by this module)

## Usage

### Basic Configuration (Recommended for Production)

```terraform
module "cloudtrail" {
  source = "../../modules/security/cloud_trail"

  env        = "production"
  project_id = "cerpac"

  # Log retention (both S3 and CloudWatch)
  retention_days = 90  # Keep logs for 90 days

  # Bucket protection
  force_destroy = false  # Prevent accidental deletion

  tags = {
    ManagedBy   = "Terraform"
    CostCenter  = "Security"
    Compliance  = "Required"
  }
}
```

### Development/Testing Configuration

```terraform
module "cloudtrail" {
  source = "../../modules/security/cloud_trail"

  env        = "development"
  project_id = "my-project"

  # Shorter retention for cost savings
  retention_days = 30

  # Allow bucket deletion in dev
  force_destroy = true

  tags = {
    Environment = "dev"
  }
}
```

### Production Configuration with Extended Retention

```terraform
module "cloudtrail" {
  source = "../../modules/security/cloud_trail"

  env        = "production"
  project_id = "cerpac"

  # Extended retention for compliance (7 years)
  retention_days = 2555

  # Bucket protection
  force_destroy = false

  tags = {
    ManagedBy   = "Terraform"
    Compliance  = "SOC2-PCI-HIPAA"
    DataClass   = "AuditLogs"
    CostCenter  = "Security"
  }
}
```

## Outputs

This module provides a single comprehensive `cloudtrail` output object containing all configuration details:

```terraform
output "cloudtrail" {
  value = {
    # S3 Bucket - Long-term audit log storage
    bucket = {
      name       = "production-cerpac-cloudtrail-logs"
      arn        = "arn:aws:s3:::production-cerpac-cloudtrail-logs"
      id         = "production-cerpac-cloudtrail-logs"
      versioning = "Enabled"
      encryption = "AES256"
    }

    # CloudWatch Log Group - Real-time log streaming
    log_group = {
      name           = "/aws/cloudtrail/production-cerpac-audit-trail"
      arn            = "arn:aws:logs:eu-west-2:123456789012:log-group:/aws/cloudtrail/..."
      retention_days = 90
    }

    # CloudTrail - Multi-region audit trail
    trail = {
      name            = "production-cerpac-audit-trail"
      arn             = "arn:aws:cloudtrail:eu-west-2:123456789012:trail/..."
      id              = "production-cerpac-audit-trail"
      is_multi_region = true
      log_validation  = true
      global_events   = true
      home_region     = "eu-west-2"
    }

    # IAM Role - CloudTrail to CloudWatch Logs
    iam_role = {
      name = "production-cerpac-cloudtrail-cloudwatch-role"
      arn  = "arn:aws:iam::123456789012:role/..."
    }

    # Configuration Summary
    summary = {
      module_enabled = true
      dual_delivery  = true
      retention_days = 90
      force_destroy  = false
    }
  }
}
```

### Using Outputs

```terraform
module "cloudtrail" {
  source = "../../modules/security/cloud_trail"
  # ...configuration...
}

# Access specific values
output "audit_bucket_name" {
  value = module.cloudtrail.cloudtrail.bucket.name
}

output "log_group_name" {
  value = module.cloudtrail.cloudtrail.log_group.name
}

output "trail_status" {
  value = {
    multi_region = module.cloudtrail.cloudtrail.trail.is_multi_region
    validation   = module.cloudtrail.cloudtrail.trail.log_validation
  }
}

# Use in CloudWatch metric filters
resource "aws_cloudwatch_log_metric_filter" "root_usage" {
  log_group_name = module.cloudtrail.cloudtrail.log_group.name
  name           = "RootAccountUsage"
  pattern        = '{ $.userIdentity.type = "Root" }'

  metric_transformation {
    name      = "RootAccountUsageCount"
    namespace = "Security"
    value     = "1"
  }
}

# Use in CloudWatch alarms
resource "aws_cloudwatch_metric_alarm" "root_usage_alarm" {
  alarm_name          = "root-account-usage"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "RootAccountUsageCount"
  namespace           = "Security"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert when root account is used"
  
  # Reference CloudTrail to ensure it's enabled
  depends_on = [module.cloudtrail]
}

# Reference in other modules
resource "aws_config_config_rule" "cloudtrail_enabled" {
  name = "cloudtrail-enabled"

  source {
    owner             = "AWS"
    source_identifier = "CLOUD_TRAIL_ENABLED"
  }

  depends_on = [module.cloudtrail]
}
```

## Cost Estimate

### Typical Production Environment

| Component | Cost | Calculation |
|-----------|------|-------------|
| **CloudTrail (First Trail)** | Free | AWS free tier |
| **S3 Storage (Standard)** | $2.30/month | 100 GB × $0.023/GB |
| **S3 PUT Requests** | $0.50/month | 100,000 PUTs × $0.005/1000 |
| **CloudWatch Logs Ingestion** | $5.00/month | 10 GB × $0.50/GB |
| **CloudWatch Logs Storage** | $3.00/month | 10 GB × $0.03/GB (90 days) |
| **Data Transfer** | $0.90/month | 10 GB × $0.09/GB (out) |
| **TOTAL** | **~$11.70/month** | |

### Cost Optimization Tips

1. **Reduce CloudWatch Retention**: Shorter retention = lower storage costs
   ```terraform
   retention_days = 30  # Instead of 90
   ```

2. **Use S3 Lifecycle to Glacier**: Archive old logs to cheaper storage
   - Modify bucket.tf to add Glacier transition
   - Save ~85% on storage costs after transition

3. **Filter Events**: Only log specific event types (advanced)
   ```terraform
   # In main.tf, modify event_selector
   event_selector {
     read_write_type           = "WriteOnly"  # Only write operations
     include_management_events = true
   }
   ```

4. **Single Region for Testing**: Disable multi-region in dev/test
   - Not recommended for production

## CloudTrail Event Types

This module captures all management events by default:

### Event Categories

| Category | Examples | Captured |
|----------|----------|----------|
| **IAM** | CreateUser, DeleteRole, AttachPolicy | ✅ Yes |
| **EC2** | RunInstances, TerminateInstances, CreateSecurityGroup | ✅ Yes |
| **S3** | CreateBucket, DeleteBucket, PutBucketPolicy | ✅ Yes |
| **RDS** | CreateDBInstance, DeleteDBSnapshot | ✅ Yes |
| **Lambda** | CreateFunction, DeleteFunction, UpdateFunctionCode | ✅ Yes |
| **VPC** | CreateVpc, DeleteSubnet, ModifySecurityGroup | ✅ Yes |
| **CloudTrail** | StopLogging, DeleteTrail (critical!) | ✅ Yes |
| **KMS** | DisableKey, ScheduleKeyDeletion | ✅ Yes |
| **Route53** | ChangeResourceRecordSets | ✅ Yes |
| **CloudFront** | CreateDistribution, UpdateDistribution | ✅ Yes |

### What's NOT Captured (by default)

- S3 object-level API activity (GetObject, PutObject) - requires data events
- Lambda function invocations - requires data events
- DynamoDB item-level operations - requires data events

To enable data events, modify the `event_selector` in main.tf.

## S3 Bucket Structure

CloudTrail logs are stored with the following structure:

```
s3://production-cerpac-cloudtrail-logs/
├── AWSLogs/
│   └── 123456789012/              # AWS Account ID
│       └── CloudTrail/
│           └── eu-west-2/         # Region
│               └── 2026/
│                   └── 01/
│                       └── 11/
│                           ├── 123456789012_CloudTrail_eu-west-2_20260111T0000Z_abc123.json.gz
│                           ├── 123456789012_CloudTrail_eu-west-2_20260111T0100Z_def456.json.gz
│                           └── 123456789012_CloudTrail_eu-west-2_20260111T0200Z_ghi789.json.gz
```

**Log File Format**: Gzip-compressed JSON  
**Delivery Frequency**: ~5-15 minutes after API call  
**File Naming**: `<AccountID>_CloudTrail_<Region>_<Timestamp>_<UniqueID>.json.gz`

## Querying CloudTrail Logs

### Method 1: CloudWatch Logs Insights (Fast, Recent Events)

**Best for**: Last 90 days, real-time troubleshooting

**Example**: Find all EC2 instance terminations

```sql
fields @timestamp, userIdentity.userName, requestParameters.instancesSet.items.0.instanceId
| filter eventName = "TerminateInstances"
| sort @timestamp desc
| limit 100
```

**Example**: Find failed API calls

```sql
fields @timestamp, eventName, errorCode, errorMessage, userIdentity.userName
| filter errorCode exists
| sort @timestamp desc
| limit 50
```

**Example**: Find root account usage

```sql
fields @timestamp, eventName, sourceIPAddress
| filter userIdentity.type = "Root"
| filter userIdentity.invokedBy not exists
| filter eventType != "AwsServiceEvent"
| sort @timestamp desc
```

### Method 2: Amazon Athena (S3, Historical Analysis)

**Best for**: Long-term forensics, compliance audits

**Step 1**: Create Athena table

```sql
CREATE EXTERNAL TABLE cloudtrail_logs (
  eventversion STRING,
  useridentity STRUCT<
    type:STRING,
    principalid:STRING,
    arn:STRING,
    accountid:STRING,
    invokedby:STRING,
    accesskeyid:STRING,
    username:STRING
  >,
  eventtime STRING,
  eventsource STRING,
  eventname STRING,
  awsregion STRING,
  sourceipaddress STRING,
  useragent STRING,
  errorcode STRING,
  errormessage STRING,
  requestparameters STRING,
  responseelements STRING,
  additionaleventdata STRING,
  requestid STRING,
  eventid STRING,
  resources ARRAY<STRUCT<
    arn:STRING,
    accountid:STRING,
    type:STRING
  >>,
  eventtype STRING,
  apiversion STRING,
  readonly STRING,
  recipientaccountid STRING,
  serviceeventdetails STRING,
  sharedeventid STRING,
  vpcendpointid STRING
)
PARTITIONED BY (region STRING, year STRING, month STRING, day STRING)
ROW FORMAT SERDE 'com.amazon.emr.hive.serde.CloudTrailSerde'
STORED AS INPUTFORMAT 'com.amazon.emr.cloudtrail.CloudTrailInputFormat'
OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION 's3://production-cerpac-cloudtrail-logs/AWSLogs/123456789012/CloudTrail/';
```

**Step 2**: Query historical data

```sql
-- Find all IAM policy changes in 2025
SELECT
  eventtime,
  useridentity.username,
  eventname,
  requestparameters
FROM cloudtrail_logs
WHERE year = '2025'
  AND eventname IN (
    'PutUserPolicy',
    'PutRolePolicy',
    'AttachRolePolicy',
    'AttachUserPolicy',
    'CreatePolicy',
    'DeletePolicy'
  )
ORDER BY eventtime DESC;
```

### Method 3: AWS CLI

**Example**: Look up specific event by ID

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventId,AttributeValue=abc-123-def-456
```

**Example**: Find events by user

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=john.doe \
  --start-time 2026-01-01T00:00:00Z \
  --end-time 2026-01-11T23:59:59Z
```

## Integration with Security Services

### 1. CloudWatch Alarms (CIS Benchmark)

```terraform
# Root account usage alarm
resource "aws_cloudwatch_log_metric_filter" "root_usage" {
  log_group_name = module.cloudtrail.cloudtrail.log_group.name
  name           = "RootAccountUsage"
  pattern        = '{ $.userIdentity.type = "Root" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != "AwsServiceEvent" }'

  metric_transformation {
    name      = "RootAccountUsageCount"
    namespace = "Security/CIS"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "root_usage" {
  alarm_name          = "cis-root-account-usage"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "RootAccountUsageCount"
  namespace           = "Security/CIS"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "CIS 1.1 - Root account usage detected"
  alarm_actions       = [var.sns_topic_arn]
}

# Unauthorized API calls alarm
resource "aws_cloudwatch_log_metric_filter" "unauthorized_calls" {
  log_group_name = module.cloudtrail.cloudtrail.log_group.name
  name           = "UnauthorizedAPICalls"
  pattern        = '{ ($.errorCode = "*UnauthorizedOperation") || ($.errorCode = "AccessDenied*") }'

  metric_transformation {
    name      = "UnauthorizedAPICallsCount"
    namespace = "Security/CIS"
    value     = "1"
  }
}

# Console login without MFA alarm
resource "aws_cloudwatch_log_metric_filter" "console_login_no_mfa" {
  log_group_name = module.cloudtrail.cloudtrail.log_group.name
  name           = "ConsoleLoginWithoutMFA"
  pattern        = '{ ($.eventName = "ConsoleLogin") && ($.additionalEventData.MFAUsed != "Yes") }'

  metric_transformation {
    name      = "ConsoleLoginWithoutMFACount"
    namespace = "Security/CIS"
    value     = "1"
  }
}
```

### 2. Amazon GuardDuty

GuardDuty automatically analyzes CloudTrail events for threats:

```terraform
resource "aws_guardduty_detector" "main" {
  enable = true

  # GuardDuty automatically uses CloudTrail
  # No explicit configuration needed
  
  depends_on = [module.cloudtrail]
}
```

### 3. AWS Security Hub

Security Hub ingests CloudTrail findings:

```terraform
resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:eu-west-2::standards/cis-aws-foundations-benchmark/v/1.4.0"
  
  depends_on = [
    aws_securityhub_account.main,
    module.cloudtrail
  ]
}
```

### 4. AWS Config

Config can check if CloudTrail is enabled:

```terraform
resource "aws_config_config_rule" "cloudtrail_enabled" {
  name = "cloudtrail-enabled"

  source {
    owner             = "AWS"
    source_identifier = "CLOUD_TRAIL_ENABLED"
  }

  depends_on = [module.cloudtrail]
}

resource "aws_config_config_rule" "cloudtrail_log_validation" {
  name = "cloudtrail-log-file-validation-enabled"

  source {
    owner             = "AWS"
    source_identifier = "CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED"
  }

  depends_on = [module.cloudtrail]
}
```

## Troubleshooting

### CloudTrail Not Logging

**Symptoms**: No logs appearing in S3 or CloudWatch

**Possible Causes**:
1. Trail is stopped
2. S3 bucket policy incorrect
3. IAM role lacks permissions
4. CloudWatch log group misconfigured

**Fix**:

```bash
# Check trail status
aws cloudtrail get-trail-status --name production-cerpac-audit-trail

# Start logging if stopped
aws cloudtrail start-logging --name production-cerpac-audit-trail

# Verify S3 bucket policy
aws s3api get-bucket-policy --bucket production-cerpac-cloudtrail-logs

# Check recent events
aws cloudtrail lookup-events --max-results 10
```

### Logs Not Appearing in CloudWatch

**Symptoms**: Logs in S3 but not CloudWatch

**Possible Causes**:
1. IAM role lacks CloudWatch permissions
2. Log group doesn't exist
3. Role ARN incorrect in trail

**Fix**:

```bash
# Verify IAM role permissions
aws iam get-role-policy \
  --role-name production-cerpac-cloudtrail-cloudwatch-role \
  --policy-name <policy-name>

# Check log group exists
aws logs describe-log-groups \
  --log-group-name-prefix /aws/cloudtrail/

# Update trail with correct role ARN
aws cloudtrail update-trail \
  --name production-cerpac-audit-trail \
  --cloud-watch-logs-role-arn arn:aws:iam::123456789012:role/...
```

### High S3 Costs

**Symptoms**: Unexpectedly high S3 storage costs

**Causes**: Large volume of logs accumulating

**Solutions**:

1. **Implement Glacier transition** (modify bucket.tf):
   ```terraform
   resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
     bucket = aws_s3_bucket.cloudtrail_logs.id

     rule {
       id     = "cloudtrail-retention"
       status = "Enabled"

       # Move to Glacier after 90 days
       transition {
         days          = 90
         storage_class = "GLACIER"
       }

       # Delete after 7 years
       expiration {
         days = 2555
       }
     }
   }
   ```

2. **Reduce retention period** (if compliance allows):
   ```terraform
   retention_days = 30  # Instead of 90
   ```

3. **Filter events** (capture only write operations):
   ```terraform
   event_selector {
     read_write_type = "WriteOnly"  # Skip read operations
   }
   ```

### Log File Validation Failures

**Symptoms**: `aws cloudtrail validate-logs` shows integrity issues

**Possible Causes**:
1. Logs tampered with
2. Logs deleted from S3
3. Digest files missing

**Investigation**:

```bash
# Validate log files
aws cloudtrail validate-logs \
  --trail-arn arn:aws:cloudtrail:eu-west-2:123456789012:trail/production-cerpac-audit-trail \
  --start-time 2026-01-01T00:00:00Z \
  --end-time 2026-01-11T23:59:59Z

# Check for deleted objects
aws s3api list-object-versions \
  --bucket production-cerpac-cloudtrail-logs \
  --prefix AWSLogs/
```

## Security Best Practices

### ✅ Implemented by This Module

- [x] Multi-region trail enabled
- [x] Global service events included
- [x] Log file validation enabled
- [x] S3 bucket versioning enabled
- [x] S3 public access blocked
- [x] Server-side encryption enabled
- [x] CloudWatch Logs integration
- [x] IAM role with least privilege

### 🔒 Recommended Enhancements

- [ ] **S3 Object Lock**: Enable WORM (Write Once Read Many) to prevent log tampering
  ```terraform
  resource "aws_s3_bucket_object_lock_configuration" "cloudtrail" {
    bucket = aws_s3_bucket.cloudtrail_logs.id

    rule {
      default_retention {
        mode = "GOVERNANCE"
        days = 2555  # 7 years
      }
    }
  }
  ```

- [ ] **KMS Encryption**: Use customer-managed keys instead of AWS-managed
  ```terraform
  resource "aws_kms_key" "cloudtrail" {
    description             = "CloudTrail log encryption"
    deletion_window_in_days = 30
    enable_key_rotation     = true
  }

  # Update in bucket.tf
  sse_algorithm     = "aws:kms"
  kms_master_key_id = aws_kms_key.cloudtrail.arn
  ```

- [ ] **Cross-Account Logging**: Send logs to separate security account

- [ ] **SNS Notifications**: Alert on log delivery
  ```terraform
  sns_topic_name = aws_sns_topic.cloudtrail_alerts.name
  ```

- [ ] **CloudTrail Insights**: Detect unusual API activity (ML-based)
  ```terraform
  insight_selector {
    insight_type = "ApiCallRateInsight"
  }
  ```

- [ ] **Separate Log Bucket**: Use dedicated account for tamper-proof logs

## Compliance Mapping

| Standard | Requirement | Status |
|----------|-------------|--------|
| **CIS AWS Foundations 3.1** | CloudTrail enabled in all regions | ✅ Met |
| **CIS AWS Foundations 3.2** | CloudTrail log file validation enabled | ✅ Met |
| **CIS AWS Foundations 3.3** | S3 bucket logging enabled | ⚠️ Optional |
| **CIS AWS Foundations 3.4** | CloudTrail logs integrated with CloudWatch | ✅ Met |
| **PCI-DSS 10.1** | Audit trail for system components | ✅ Met |
| **PCI-DSS 10.2** | Automated audit trail for all users | ✅ Met |
| **PCI-DSS 10.3** | Audit trail includes date, user, event | ✅ Met |
| **HIPAA 164.312(b)** | Audit controls | ✅ Met |
| **SOC 2 CC7.2** | System monitoring | ✅ Met |
| **GDPR Article 33** | Breach detection within 72 hours | ✅ Met (with alarms) |
| **ISO 27001 A.12.4.1** | Event logging | ✅ Met |
| **NIST 800-53 AU-2** | Audit events | ✅ Met |

## Variables Reference

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `env` | string | Required | Environment name (production, staging, development) |
| `project_id` | string | Required | Project identifier for resource naming |
| `retention_days` | number | `90` | Log retention period in days |
| `force_destroy` | bool | `false` | Allow S3 bucket destruction even with logs |
| `tags` | map(string) | `{}` | Additional tags for all resources |

## Example: Complete Security Monitoring Setup

```terraform
# CloudTrail module
module "cloudtrail" {
  source = "../../modules/security/cloud_trail"

  env            = "production"
  project_id     = "cerpac"
  retention_days = 90
  force_destroy  = false
}

# SNS topic for security alerts
resource "aws_sns_topic" "security_alerts" {
  name = "production-security-alerts"
}

resource "aws_sns_topic_subscription" "security_email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = "security@company.com"
}

# CIS Benchmark alarms
module "cis_alarms" {
  source = "../../modules/security/cis_alarms"

  log_group_name = module.cloudtrail.cloudtrail.log_group.name
  sns_topic_arn  = aws_sns_topic.security_alerts.arn
}

# GuardDuty
resource "aws_guardduty_detector" "main" {
  enable = true
}

# Security Hub
resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:::standards/cis-aws-foundations-benchmark/v/1.4.0"
}

# AWS Config
module "aws_config" {
  source = "../../modules/security/aws_config"

  env        = "production"
  project_id = "cerpac"
}
```

## Related Modules

- **AWS Config**: Configuration compliance monitoring
- **GuardDuty**: ML-based threat detection
- **Security Hub**: Centralized security findings
- **CIS Alarms**: CloudWatch alarms for CIS benchmark

## Best Practices Summary

✅ **Enable in all regions** (multi-region trail)  
✅ **Enable log file validation** (tamper detection)  
✅ **Use S3 versioning** (protect audit trail)  
✅ **Set up CloudWatch integration** (real-time alerts)  
✅ **Implement retention policies** (compliance + cost optimization)  
✅ **Monitor trail status** (ensure logging never stops)  
✅ **Set up alarms for critical events** (root usage, unauthorized calls, etc.)  
✅ **Keep logs for 7 years** (compliance requirement)  
✅ **Never disable CloudTrail** (creates audit blind spots)  

## Support

For issues or questions:
- Internal: Contact Security Team
- Documentation: See [AWS CloudTrail Documentation](https://docs.aws.amazon.com/cloudtrail/)
- Related: [CloudTrail Security Guide](./cloud_trail.md)

---

**Last Updated**: January 11, 2026  
**Version**: 1.0.0  
**Maintained By**: Security Team

