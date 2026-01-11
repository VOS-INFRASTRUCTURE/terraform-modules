# AWS Config Terraform Module

Terraform module to enable and configure AWS Config for continuous configuration monitoring and compliance auditing.

## Overview

AWS Config continuously monitors and records AWS resource configurations, enabling:

- **Configuration History**: Track how resources change over time
- **Compliance Auditing**: Automatically check if resources meet your policies
- **Change Management**: Detect when configurations drift from desired state
- **Security Posture**: Identify security misconfigurations
- **Relationship Tracking**: Understand dependencies between resources

## Module Structure

```
aws_config/
├── main.tf       # Configuration Recorder, Delivery Channel, and Recorder Status
├── bucket.tf     # S3 bucket configuration for Config logs
├── variables.tf  # Input variables
├── outputs.tf    # Module outputs (single 'config' object)
└── README.md     # This file
```

## Features

✅ **S3 Bucket**: Secure storage for configuration snapshots and history  
✅ **Configuration Recorder**: Records changes for all supported AWS resources  
✅ **Delivery Channel**: Delivers configuration data to S3 (and optionally SNS)  
✅ **Lifecycle Policy**: Automatic transition to Glacier and log expiration  
✅ **Encryption**: Server-side encryption (AES256 or KMS)  
✅ **Versioning**: Optional S3 versioning for audit trail protection  
✅ **SNS Notifications**: Optional real-time alerts on configuration changes  

## Prerequisites

- AWS Config service-linked role (created automatically on first use)
- S3 bucket permissions (handled by this module)
- (Optional) SNS topic for notifications

## Usage

### Basic Configuration (Recommended for Production)

```terraform
module "aws_config" {
  source = "../../modules/security/aws_config"

  env        = "production"
  project_id = "cerpac"

  # Enable AWS Config
  enable_aws_config = true

  # S3 Bucket Configuration
  enable_bucket_versioning = true
  force_destroy_bucket     = false  # Protect against accidental deletion

  # Lifecycle Policy (Cost Optimization)
  enable_lifecycle_policy  = true
  glacier_transition_days  = 90    # Move to Glacier after 90 days
  log_expiration_days      = 2555  # Keep for 7 years (compliance)

  # Recording Configuration
  record_all_resources     = true  # Record all supported resource types
  include_global_resources = true  # Include IAM, etc. (enable in ONE region only)

  # Delivery Configuration
  snapshot_delivery_frequency = "TwentyFour_Hours"

  # Optional: SNS Notifications
  # sns_topic_arn = aws_sns_topic.config_alerts.arn

  tags = {
    ManagedBy   = "Terraform"
    CostCenter  = "Security"
    Compliance  = "Required"
  }
}
```

### Minimal Configuration (Development/Testing)

```terraform
module "aws_config" {
  source = "../../modules/security/aws_config"

  env        = "development"
  project_id = "my-project"

  enable_aws_config        = true
  enable_bucket_versioning = false
  force_destroy_bucket     = true  # Allow bucket deletion in dev

  # Shorter retention for cost savings
  glacier_transition_days = 30
  log_expiration_days     = 365

  tags = {
    Environment = "dev"
  }
}
```

### Selective Resource Recording (Cost Optimization)

```terraform
module "aws_config" {
  source = "../../modules/security/aws_config"

  env        = "production"
  project_id = "cerpac"

  # Only record specific resource types
  record_all_resources = false
  resource_types = [
    "AWS::EC2::Instance",
    "AWS::EC2::SecurityGroup",
    "AWS::S3::Bucket",
    "AWS::RDS::DBInstance",
    "AWS::IAM::User",
    "AWS::IAM::Role",
    "AWS::Lambda::Function",
  ]

  include_global_resources = true
}
```

### With SNS Notifications

```terraform
# Create SNS topic for Config notifications
resource "aws_sns_topic" "config_alerts" {
  name = "production-aws-config-alerts"

  tags = {
    Environment = "production"
    Purpose     = "AWS Config notifications"
  }
}

resource "aws_sns_topic_subscription" "config_email" {
  topic_arn = aws_sns_topic.config_alerts.arn
  protocol  = "email"
  endpoint  = "security@company.com"
}

module "aws_config" {
  source = "../../modules/security/aws_config"

  env        = "production"
  project_id = "cerpac"

  # Enable SNS notifications
  sns_topic_arn = aws_sns_topic.config_alerts.arn

  # ...other configuration...
}
```

### With KMS Encryption

```terraform
resource "aws_kms_key" "config_logs" {
  description             = "KMS key for AWS Config logs encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Environment = "production"
    Purpose     = "AWS Config encryption"
  }
}

module "aws_config" {
  source = "../../modules/security/aws_config"

  env        = "production"
  project_id = "cerpac"

  # Use KMS encryption instead of AES256
  kms_key_arn = aws_kms_key.config_logs.arn

  # ...other configuration...
}
```

## Multi-Region Deployment

**IMPORTANT**: When deploying AWS Config in multiple regions:

1. **Enable `include_global_resources` in ONE region only** (typically primary region like `us-east-1` or `eu-west-1`)
2. **Set `include_global_resources = false` in all other regions**

This prevents duplicate recording of global resources like IAM users, roles, and policies.

### Example: Multi-Region Setup

```terraform
# Primary region (eu-west-1) - Include global resources
module "aws_config_primary" {
  source = "../../modules/security/aws_config"
  
  providers = {
    aws = aws.eu-west-1
  }

  env        = "production"
  project_id = "cerpac"

  include_global_resources = true  # ✅ Enable here
  record_all_resources     = true

  # ...other configuration...
}

# Secondary region (eu-west-2) - Exclude global resources
module "aws_config_secondary" {
  source = "../../modules/security/aws_config"
  
  providers = {
    aws = aws.eu-west-2
  }

  env        = "production"
  project_id = "cerpac"

  include_global_resources = false  # ❌ Disable here
  record_all_resources     = true

  # ...other configuration...
}
```

## Outputs

This module provides a single comprehensive `config` output object containing all configuration details:

```terraform
output "config" {
  value = {
    # S3 Bucket - Configuration log storage
    bucket = {
      name       = "production-cerpac-aws-config-logs"
      arn        = "arn:aws:s3:::production-cerpac-aws-config-logs"
      id         = "production-cerpac-aws-config-logs"
      versioning = true
      encryption = "AES256"  # or "KMS" if KMS key is used
    }

    # Configuration Recorder - Records resource configurations
    recorder = {
      name                     = "production-cerpac-config-recorder"
      role_arn                 = "arn:aws:iam::123456789012:role/..."
      record_all_resources     = true
      include_global_resources = true
      resource_types           = []
      is_enabled               = true
    }

    # Delivery Channel - Delivers configuration snapshots
    delivery_channel = {
      name               = "production-cerpac-config-delivery"
      s3_bucket_name     = "production-cerpac-aws-config-logs"
      s3_key_prefix      = ""
      snapshot_frequency = "TwentyFour_Hours"
      sns_topic_arn      = null  # or SNS topic ARN if configured
    }

    # Lifecycle Policy - Cost optimization settings
    lifecycle = {
      enabled                 = true
      glacier_transition_days = 90
      log_expiration_days     = 2555
    }

    # Account Information
    account = {
      account_id = "123456789012"
      region     = "eu-west-2"
    }

    # Configuration Summary
    summary = {
      module_enabled       = true
      recording_active     = true
      notifications_active = false  # true if SNS topic configured
      cost_optimization    = true
    }
  }
}
```

### Using Outputs

```terraform
module "aws_config" {
  source = "../../modules/security/aws_config"
  # ...configuration...
}

# Access specific values
output "config_bucket_name" {
  value = module.aws_config.config.bucket.name
}

output "is_recording" {
  value = module.aws_config.config.recorder.is_enabled
}

output "account_info" {
  value = module.aws_config.config.account
}

# Or use the entire config object
output "full_config" {
  value = module.aws_config.config
}

# Reference in other resources
resource "aws_config_config_rule" "restricted_ssh" {
  name = "restricted-ssh"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  # Ensure Config is enabled before creating rules
  depends_on = [module.aws_config]
}
```

## Cost Estimate

### Typical Production Environment

| Component | Cost | Calculation |
|-----------|------|-------------|
| **Configuration Items** | $30/month | 10,000 items × $0.003 |
| **Config Rule Evaluations** | $100/month | 100,000 evals × $0.001 |
| **S3 Storage (Standard)** | $1.15/month | 50 GB × $0.023 |
| **S3 Storage (Glacier)** | $0.20/month | 50 GB × $0.004 (after 90 days) |
| **S3 API Requests** | $0.50/month | 100,000 PUTs × $0.005/1000 |
| **SNS Notifications** | Free | <1M messages/month |
| **TOTAL** | **~$131/month** | |

### Cost Optimization Tips

1. **Selective Recording**: Only record resource types you need
   ```terraform
   record_all_resources = false
   resource_types = ["AWS::EC2::Instance", "AWS::S3::Bucket"]
   ```

2. **Lifecycle Policy**: Move old logs to Glacier
   ```terraform
   glacier_transition_days = 90  # Saves ~85% on storage costs
   ```

3. **Snapshot Frequency**: Reduce snapshot frequency
   ```terraform
   snapshot_delivery_frequency = "TwentyFour_Hours"  # vs One_Hour
   ```

4. **Log Expiration**: Delete very old logs
   ```terraform
   log_expiration_days = 2555  # 7 years (or less if compliance allows)
   ```

## Configuration Recorder Status

Check if AWS Config is recording:

```bash
# Check recorder status
aws configservice describe-configuration-recorder-status

# Check delivery channel status
aws configservice describe-delivery-channel-status

# Stop recording (if needed)
aws configservice stop-configuration-recorder \
  --configuration-recorder-name production-cerpac-config-recorder

# Start recording
aws configservice start-configuration-recorder \
  --configuration-recorder-name production-cerpac-config-recorder
```

## S3 Bucket Structure

Configuration logs are stored with the following structure:

```
s3://production-cerpac-aws-config-logs/
├── AWSLogs/
│   └── 123456789012/              # AWS Account ID
│       └── Config/
│           └── eu-west-2/         # Region
│               └── 2026/
│                   └── 1/
│                       └── 11/
│                           ├── ConfigSnapshot/
│                           │   └── 123456789012_Config_eu-west-2_ConfigSnapshot_20260111T120000Z.json.gz
│                           └── ConfigHistory/
│                               └── AWS::EC2::Instance/
│                                   └── i-0123456789abcdef_20260111T120000Z.json.gz
```

## Querying Configuration Data

### AWS Console

1. Navigate to **AWS Config** → **Resources**
2. Select resource type (e.g., EC2 Instance)
3. View configuration timeline and compliance status

### AWS CLI

```bash
# Get resource configuration
aws configservice get-resource-config-history \
  --resource-type AWS::EC2::SecurityGroup \
  --resource-id sg-0123456789abcdef0

# List all recorded resources
aws configservice list-discovered-resources \
  --resource-type AWS::EC2::Instance
```

### AWS Config Advanced Queries (SQL)

```sql
-- Find all unencrypted S3 buckets
SELECT
  resourceId,
  resourceName,
  configuration.serverSideEncryptionConfiguration
WHERE
  resourceType = 'AWS::S3::Bucket'
  AND configuration.serverSideEncryptionConfiguration IS NULL

-- Find all public EC2 instances
SELECT
  resourceId,
  configuration.publicIpAddress,
  tags
WHERE
  resourceType = 'AWS::EC2::Instance'
  AND configuration.publicIpAddress IS NOT NULL
```

## Troubleshooting

### Recorder Not Starting

**Error**: `ConfigurationRecorderStartException`

**Cause**: Delivery channel not configured or S3 bucket policy missing

**Fix**:
1. Verify S3 bucket exists and has correct policy
2. Check `depends_on` in delivery channel
3. Wait 1-2 minutes after bucket policy creation

### Permission Denied Errors

**Error**: `AccessDenied` when Config tries to write to S3

**Cause**: Bucket policy missing or incorrect

**Fix**: Verify bucket policy includes:
- `s3:GetBucketAcl` permission
- `s3:PutObject` permission with `s3:x-amz-acl` condition

### High Costs

**Issue**: Config costs higher than expected

**Solutions**:
1. Reduce recorded resource types (set `record_all_resources = false`)
2. Disable unused Config Rules
3. Increase `glacier_transition_days` to move logs to cheaper storage faster
4. Review `snapshot_delivery_frequency` (reduce if possible)

### Duplicate Global Resources

**Issue**: IAM resources recorded twice (different regions)

**Fix**: Enable `include_global_resources` in ONE region only

## Related Modules

- **CloudTrail**: API call auditing (complements AWS Config)
- **GuardDuty**: Threat detection
- **Security Hub**: Centralized security findings
- **Config Rules**: Compliance automation (deploy separately)

## Compliance Standards

This module helps meet requirements for:

- ✅ **CIS AWS Foundations Benchmark**
- ✅ **PCI-DSS** (configuration monitoring)
- ✅ **HIPAA** (audit controls)
- ✅ **SOC 2** (change tracking)
- ✅ **GDPR** (data governance)
- ✅ **ISO 27001** (configuration management)

## Variables Reference

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_aws_config` | bool | `true` | Enable/disable AWS Config |
| `env` | string | Required | Environment name |
| `project_id` | string | Required | Project identifier |
| `tags` | map(string) | `{}` | Additional tags |
| `force_destroy_bucket` | bool | `false` | Allow S3 bucket destruction |
| `enable_bucket_versioning` | bool | `true` | Enable S3 versioning |
| `kms_key_arn` | string | `null` | KMS key for encryption |
| `s3_key_prefix` | string | `""` | S3 key prefix |
| `enable_lifecycle_policy` | bool | `true` | Enable lifecycle policy |
| `glacier_transition_days` | number | `90` | Days before Glacier transition |
| `log_expiration_days` | number | `2555` | Days before log deletion |
| `record_all_resources` | bool | `true` | Record all resource types |
| `include_global_resources` | bool | `true` | Include global resources |
| `resource_types` | list(string) | `[]` | Specific resource types |
| `config_role_arn` | string | `null` | Custom IAM role ARN |
| `snapshot_delivery_frequency` | string | `TwentyFour_Hours` | Snapshot frequency |
| `sns_topic_arn` | string | `null` | SNS topic for notifications |

## Best Practices

✅ **Enable in all regions** (for complete coverage)  
✅ **Enable versioning** on S3 bucket (protect audit trail)  
✅ **Use lifecycle policies** (cost optimization)  
✅ **Set up SNS alerts** (real-time notifications)  
✅ **Enable global resources in ONE region only** (avoid duplicates)  
✅ **Review compliance dashboard weekly**  
✅ **Keep logs for 7 years** (compliance requirement)  
✅ **Combine with CloudTrail** (complete audit coverage)  

## Security Considerations

- S3 bucket has public access blocked
- Server-side encryption enabled by default
- Bucket policy restricts access to AWS Config service only
- Optional KMS encryption for enhanced security
- Versioning protects against accidental deletion
- Lifecycle policy for compliance retention

## License

This module is maintained by the Security Team.

## Support

For issues or questions:
- Internal: Contact Security Team
- Documentation: See [AWS Config Documentation](https://docs.aws.amazon.com/config/)

---

**Last Updated**: January 11, 2026  
**Version**: 1.0.0  
**Maintained By**: Security Team

