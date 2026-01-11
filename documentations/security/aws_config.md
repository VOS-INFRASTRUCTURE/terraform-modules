# AWS Config - Continuous Compliance Monitoring

## Overview

AWS Config is a service that enables you to assess, audit, and evaluate the configurations of your AWS resources. It continuously monitors and records your AWS resource configurations and allows you to automate the evaluation of recorded configurations against desired configurations.

## Purpose

AWS Config provides continuous compliance monitoring and governance capabilities:

- **Configuration History**: Track how resources change over time
- **Compliance Auditing**: Automatically check if resources meet your policies
- **Change Management**: Detect when configurations drift from desired state
- **Security Posture**: Identify security misconfigurations before they're exploited
- **Relationship Tracking**: Understand dependencies between resources
- **Troubleshooting**: Debug issues by reviewing configuration history

---

## How AWS Config Works

```
AWS Resources (EC2, S3, RDS, etc.)
         ↓
  Configuration Changes Detected
         ↓
AWS Config Records Configuration
         ↓
Stores in S3 + Configuration History DB
         ↓
Evaluates Against Config Rules
         ↓
Non-Compliant? → SNS Notification → Security Team
         ↓
Compliance Dashboard (AWS Console)
```

### Key Concepts

1. **Configuration Items (CIs)**: Point-in-time snapshot of a resource's configuration
2. **Configuration Recorder**: Records configuration changes for specified resource types
3. **Delivery Channel**: Sends configuration snapshots and change notifications to S3/SNS
4. **Config Rules**: Automated compliance checks (AWS Managed or Custom)
5. **Conformance Packs**: Collections of Config Rules for specific compliance standards

---

## Configuration in CERPAC Production

### Configuration Recorder

**What it records**: All supported AWS resources in the account

**Supported Resources** (150+ types):
- Compute: EC2, Lambda, ECS
- Storage: S3, EBS, EFS
- Database: RDS, DynamoDB
- Network: VPC, Security Groups, NACLs, ALB/NLB
- Security: IAM, KMS, Secrets Manager, WAF
- And many more...

**Recording Frequency**:
- **Continuous**: Most resources (triggered on configuration change)
- **Periodic**: Some resources (every 24 hours)

**Multi-Region**: Typically enabled in all regions to ensure complete coverage

---

### Delivery Channel Configuration

#### S3 Bucket for Configuration History

**Bucket Name**: `production-cerpac-config-logs` (or similar)

**Purpose**: Store configuration snapshots and change history

**Structure**:
```
s3://production-cerpac-config-logs/
  AWSLogs/
    <account-id>/
      Config/
        <region>/
          <year>/<month>/<day>/
            ConfigSnapshot/
              <timestamp>_ConfigSnapshot.json.gz
            ConfigHistory/
              <resource-id>_<timestamp>.json.gz
```

**Features**:
- **Versioning Enabled**: Protect against accidental deletion
- **Encryption**: SSE-S3 or SSE-KMS
- **Lifecycle Policy**: 
  - Transition to Glacier after 90 days
  - Retain for 7 years (compliance)
- **Access Logging**: Track who accesses configuration data

#### SNS Topic for Change Notifications

**Topic Name**: `production-cerpac-config-notifications`

**Notifications Sent For**:
- Configuration changes detected
- Compliance evaluation results
- Config rule violations

**Subscribers**:
- Security team email
- CloudWatch Logs (for metric filters)
- Lambda functions (for automated remediation)

---

## Config Rules - Compliance Checks

AWS Config Rules continuously evaluate your resources for compliance. Here are common rules for production environments:

### 1. Security Group Rules

#### `restricted-ssh` (AWS Managed Rule)

**Checks**: Security groups don't allow unrestricted SSH (0.0.0.0/0 on port 22)

**Why**: Prevents brute-force attacks and unauthorized access

**Remediation**: Update security group to allow SSH only from corporate IP ranges

```terraform
# Compliant
ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["203.0.113.0/24"]  # Corporate VPN only
}

# Non-compliant
ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]  # ❌ Public SSH access
}
```

#### `restricted-common-ports` (AWS Managed Rule)

**Checks**: Security groups don't allow unrestricted access to common ports (RDP 3389, MySQL 3306, PostgreSQL 5432, etc.)

**Why**: Databases and management ports should never be public

**Parameters**:
- `blockedPort1`: 3389 (RDP)
- `blockedPort2`: 3306 (MySQL)
- `blockedPort3`: 5432 (PostgreSQL)

---

### 2. S3 Bucket Security

#### `s3-bucket-public-read-prohibited` (AWS Managed Rule)

**Checks**: S3 buckets don't allow public read access

**Why**: Prevents data leaks and unauthorized access to sensitive files

**Non-compliant Examples**:
- Bucket policy with `"Principal": "*"` and `"Action": "s3:GetObject"`
- ACL allowing public read access

#### `s3-bucket-public-write-prohibited` (AWS Managed Rule)

**Checks**: S3 buckets don't allow public write access

**Why**: Prevents attackers from uploading malicious content or consuming your storage

#### `s3-bucket-versioning-enabled` (AWS Managed Rule)

**Checks**: S3 buckets have versioning enabled

**Why**: Protects against accidental deletion and provides rollback capability

#### `s3-bucket-server-side-encryption-enabled` (AWS Managed Rule)

**Checks**: S3 buckets have default encryption enabled

**Why**: Ensures data at rest is encrypted (compliance requirement)

---

### 3. EC2 Compliance

#### `ec2-instance-managed-by-systems-manager` (AWS Managed Rule)

**Checks**: EC2 instances are registered with AWS Systems Manager

**Why**: Enables centralized patch management and security scanning

#### `ec2-volume-inuse-check` (AWS Managed Rule)

**Checks**: EBS volumes are attached to EC2 instances

**Why**: Detects orphaned volumes (wasted cost + potential data leak risk)

#### `encrypted-volumes` (AWS Managed Rule)

**Checks**: EBS volumes are encrypted

**Why**: Protects data at rest (compliance requirement)

---

### 4. RDS Database Security

#### `rds-instance-public-access-check` (AWS Managed Rule)

**Checks**: RDS instances are not publicly accessible

**Why**: Databases should only be accessible from private subnets

**Compliant**:
```terraform
resource "aws_db_instance" "main" {
  publicly_accessible = false  # ✅ Private only
  # ...
}
```

#### `rds-storage-encrypted` (AWS Managed Rule)

**Checks**: RDS instances have encryption at rest enabled

**Why**: Protects sensitive data (PII, financial records, etc.)

#### `rds-snapshots-public-prohibited` (AWS Managed Rule)

**Checks**: RDS snapshots are not public

**Why**: Prevents accidental data exposure through snapshot sharing

#### `db-instance-backup-enabled` (AWS Managed Rule)

**Checks**: RDS instances have automated backups enabled

**Why**: Ensures disaster recovery capability

---

### 5. IAM Security

#### `iam-password-policy` (AWS Managed Rule)

**Checks**: IAM password policy meets minimum requirements

**Parameters**:
- Minimum password length: 14 characters
- Require uppercase: Yes
- Require lowercase: Yes
- Require numbers: Yes
- Require symbols: Yes
- Password expiration: 90 days
- Password reuse prevention: 5 passwords

**Why**: Strong passwords reduce brute-force risk

#### `iam-user-mfa-enabled` (AWS Managed Rule)

**Checks**: IAM users have MFA enabled

**Why**: Prevents account takeover even if password is stolen

#### `iam-root-access-key-check` (AWS Managed Rule)

**Checks**: Root user does not have access keys

**Why**: Root access keys are extremely dangerous (unlimited permissions)

#### `access-keys-rotated` (AWS Managed Rule)

**Checks**: IAM access keys are rotated within specified days (default: 90)

**Why**: Limits damage window if keys are compromised

---

### 6. CloudTrail Monitoring

#### `cloud-trail-enabled` (AWS Managed Rule)

**Checks**: CloudTrail is enabled in all regions

**Why**: Ensures audit logging is active

#### `cloud-trail-log-file-validation-enabled` (AWS Managed Rule)

**Checks**: CloudTrail log file validation is enabled

**Why**: Detects log tampering via cryptographic hashing

---

### 7. KMS Encryption

#### `cmk-backing-key-rotation-enabled` (AWS Managed Rule)

**Checks**: KMS Customer Master Keys have automatic rotation enabled

**Why**: Reduces risk of key compromise over time

---

### 8. VPC Security

#### `vpc-flow-logs-enabled` (AWS Managed Rule)

**Checks**: VPCs have Flow Logs enabled

**Why**: Network traffic monitoring for security analysis

#### `vpc-default-security-group-closed` (AWS Managed Rule)

**Checks**: Default security group blocks all traffic

**Why**: Forces explicit security group creation (prevents accidental exposure)

---

## Conformance Packs

Conformance Packs are pre-built collections of Config Rules for specific compliance frameworks.

### CIS AWS Foundations Benchmark

**Rules Included** (20+ rules):
- IAM password policy
- MFA for root and users
- CloudTrail enabled and validated
- S3 bucket encryption and logging
- VPC flow logs enabled
- Security group restrictions

**Deployment**:
```terraform
resource "aws_config_conformance_pack" "cis_benchmark" {
  name = "cis-aws-foundations-benchmark"
  
  template_body = file("${path.module}/conformance-packs/cis-aws-foundations.yaml")
  
  # Optional: Parameters to customize rules
  input_parameter {
    parameter_name  = "AccessKeysRotatedParamMaxAccessKeyAge"
    parameter_value = "90"
  }
}
```

### PCI-DSS Conformance Pack

**For**: Payment card data processing environments

**Key Rules**:
- Encrypted storage (EBS, RDS, S3)
- Network isolation (security groups, NACLs)
- Audit logging (CloudTrail, VPC Flow Logs)
- Access control (IAM, MFA)

---

## Remediation Strategies

### 1. Manual Remediation

**When**: For sensitive changes requiring human review

**Process**:
1. Receive SNS notification of non-compliance
2. Review Config Rule details in AWS Console
3. Manually fix the configuration
4. Verify compliance status updates

**Example**: Security group allows 0.0.0.0/0 on SSH
- Action: Update security group rules to restrict source IPs

---

### 2. AWS Systems Manager Automation (SSM)

**When**: For standardized, repeatable fixes

**How it works**:
1. Config Rule detects non-compliance
2. Triggers SSM Automation Document
3. Automation fixes the resource automatically

**Example**: Unencrypted EBS volume detected
- Automation: Create encrypted snapshot → Create encrypted volume → Swap volumes

**Setup**:
```terraform
resource "aws_config_remediation_configuration" "encrypt_ebs_volume" {
  config_rule_name = aws_config_config_rule.encrypted_volumes.name
  
  target_type      = "SSM_DOCUMENT"
  target_id        = "AWS-EnableEBSEncryptionByDefault"
  target_version   = "1"
  
  automatic                  = true  # Auto-remediate
  maximum_automatic_attempts = 5
  retry_attempt_seconds      = 60
}
```

---

### 3. Lambda-Based Remediation

**When**: For complex remediation logic

**Example**: S3 bucket becomes public
- Lambda function: Remove public bucket policy + send detailed alert

**Setup**:
```terraform
resource "aws_cloudwatch_event_rule" "s3_public_bucket" {
  name        = "s3-bucket-public-alert"
  description = "Trigger Lambda when S3 bucket becomes public"
  
  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      configRuleName = ["s3-bucket-public-read-prohibited"]
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "remediate_s3_public" {
  rule      = aws_cloudwatch_event_rule.s3_public_bucket.name
  target_id = "RemediateS3Public"
  arn       = aws_lambda_function.remediate_s3_public.arn
}
```

---

## Multi-Account Configuration

For organizations with multiple AWS accounts:

### AWS Config Aggregator

**Purpose**: Centralize compliance data from multiple accounts/regions

**Setup**:
1. **Organization aggregator** (recommended): Automatically includes all accounts in AWS Organization
2. **Manual aggregator**: Explicitly specify account IDs

**Benefits**:
- Single dashboard for entire organization
- Cross-account compliance reporting
- Easier audit evidence collection

**Terraform Example**:
```terraform
resource "aws_config_configuration_aggregator" "organization" {
  name = "organization-config-aggregator"
  
  organization_aggregation_source {
    all_regions = true
    role_arn    = aws_iam_role.config_aggregator.arn
  }
}
```

---

## Cost Breakdown

| Component | Cost | Calculation |
|-----------|------|-------------|
| **Configuration Items Recorded** | $0.003 per CI | 10,000 CIs/month = $30 |
| **Config Rule Evaluations** | $0.001 per evaluation | 100,000 evals/month = $100 |
| **Conformance Pack Evaluations** | $0.0012 per evaluation | (included in rule cost) |
| **S3 Storage** | $0.023/GB | 50 GB/month = $1.15 |
| **S3 API Requests** | $0.005 per 1,000 PUT | 100,000 PUTs = $0.50 |
| **SNS Notifications** | $0.50 per 1M | 10,000 notifs = $0.005 |
| **TOTAL (Typical Production)** | **~$131.65/month** | |

**Cost Optimization Tips**:
1. **Selective Recording**: Only record resource types you need to monitor
2. **Rule Optimization**: Disable unused rules
3. **Periodic Rules**: Use periodic evaluation instead of continuous for non-critical checks
4. **S3 Lifecycle**: Move old configuration snapshots to Glacier after 90 days

---

## Config vs. CloudTrail vs. GuardDuty

| Feature | AWS Config | CloudTrail | GuardDuty |
|---------|-----------|-----------|-----------|
| **What it monitors** | Resource configurations | API calls and user activity | Threats and anomalies |
| **Primary use case** | Compliance auditing | Audit logging | Security threat detection |
| **Detection type** | Policy-based (rules) | Event-based (logs) | ML-based (anomalies) |
| **Response time** | Minutes (rule evaluation) | Real-time (events) | Near real-time (findings) |
| **Remediation** | Can trigger automation | Read-only (no auto-fix) | Alerts only |
| **Cost** | ~$130/month | ~$11/month | ~$50-500/month |
| **Best for** | "Is my infrastructure configured correctly?" | "Who did what and when?" | "Am I under attack?" |

**Recommendation**: Use all three together for comprehensive security coverage.

---

## Querying Configuration Data

### AWS Config Console

**Navigate**: AWS Config → Resources → Select resource type

**View**:
- Current configuration
- Configuration timeline (historical changes)
- Compliance status
- Related resources

### AWS Config Advanced Queries (SQL)

**Example**: Find all unencrypted S3 buckets

```sql
SELECT
  resourceId,
  resourceName,
  resourceType,
  configuration.serverSideEncryptionConfiguration
WHERE
  resourceType = 'AWS::S3::Bucket'
  AND configuration.serverSideEncryptionConfiguration IS NULL
```

**Example**: Find all public EC2 instances

```sql
SELECT
  resourceId,
  configuration.publicIpAddress,
  configuration.privateIpAddress,
  tags
WHERE
  resourceType = 'AWS::EC2::Instance'
  AND configuration.publicIpAddress IS NOT NULL
```

### AWS CLI

**Get compliance summary**:
```bash
aws configservice describe-compliance-by-config-rule \
  --config-rule-names restricted-ssh s3-bucket-public-read-prohibited
```

**Get resource configuration history**:
```bash
aws configservice get-resource-config-history \
  --resource-type AWS::EC2::SecurityGroup \
  --resource-id sg-0123456789abcdef0 \
  --limit 10
```

---

## Integration with Other Services

### 1. AWS Security Hub

- **Purpose**: Centralized security findings dashboard
- **Integration**: Config findings appear as Security Hub insights
- **Benefit**: Unified view of compliance + vulnerabilities + threats

### 2. AWS Systems Manager

- **Purpose**: Automated remediation
- **Integration**: Config triggers SSM Automation Documents
- **Benefit**: Self-healing infrastructure

### 3. Amazon EventBridge (CloudWatch Events)

- **Purpose**: Event-driven workflows
- **Integration**: Config compliance changes trigger EventBridge rules
- **Benefit**: Custom automation (Lambda, Step Functions, etc.)

### 4. AWS Organizations

- **Purpose**: Multi-account governance
- **Integration**: Config Aggregator + Organization-wide Config Rules
- **Benefit**: Centralized compliance enforcement

---

## Common Use Cases

### 1. Continuous Compliance Monitoring

**Scenario**: Ensure all resources meet CIS Benchmark standards

**Solution**:
- Enable CIS Conformance Pack
- Set up SNS alerts for non-compliance
- Review compliance dashboard weekly

### 2. Change Management

**Scenario**: Track who changed security group rules and when

**Solution**:
- Enable Config Recorder for EC2::SecurityGroup
- Query configuration timeline in Config console
- Cross-reference with CloudTrail for user identity

### 3. Disaster Recovery Validation

**Scenario**: Verify RDS backups are enabled for all databases

**Solution**:
- Enable `db-instance-backup-enabled` rule
- Automated alerts if backup is disabled
- Quarterly compliance report for auditors

### 4. Security Posture Assessment

**Scenario**: Identify all publicly accessible resources

**Solution**:
- Enable rules: `rds-instance-public-access-check`, `restricted-ssh`, `s3-bucket-public-read-prohibited`
- Run Config Advanced Query to find public resources
- Remediate via Lambda or SSM

### 5. Audit Evidence Collection

**Scenario**: Provide proof of compliance for SOC 2 audit

**Solution**:
- Export Config compliance reports
- Show configuration timeline for critical resources
- Demonstrate continuous monitoring via SNS alerts

---

## Troubleshooting

### Config Recorder Not Recording

**Symptoms**: No configuration items appearing

**Causes**:
1. Config Recorder is stopped
2. IAM role lacks permissions
3. Delivery channel not configured

**Fix**:
```bash
# Check recorder status
aws configservice describe-configuration-recorder-status

# Start recorder
aws configservice start-configuration-recorder \
  --configuration-recorder-name default
```

### Rules Always Showing Non-Compliant

**Symptoms**: Resources are compliant but rule shows non-compliant

**Causes**:
1. Rule parameters incorrectly configured
2. Eventual consistency delay (wait 5-10 minutes)
3. Bug in custom Lambda rule

**Fix**:
- Re-evaluate rule manually in console
- Check rule parameters
- Review Lambda function logs (if custom rule)

### High Costs

**Symptoms**: Config bill is unexpectedly high

**Causes**:
1. Recording unnecessary resource types
2. Too many rule evaluations
3. Continuous evaluation for periodic-suitable rules

**Fix**:
```terraform
# Selective resource recording
resource "aws_config_configuration_recorder" "main" {
  name     = "production-config-recorder"
  role_arn = aws_iam_role.config.arn
  
  recording_group {
    all_supported                 = false  # Don't record everything
    include_global_resource_types = true
    
    # Only record critical resource types
    resource_types = [
      "AWS::EC2::Instance",
      "AWS::EC2::SecurityGroup",
      "AWS::S3::Bucket",
      "AWS::RDS::DBInstance",
      "AWS::IAM::User",
      "AWS::IAM::Role",
    ]
  }
}
```

---

## Best Practices

### ✅ Do

- [x] Enable Config in all regions (multi-region threats)
- [x] Use AWS Managed Rules (pre-tested, maintained by AWS)
- [x] Enable S3 bucket versioning (protect config data)
- [x] Set up SNS notifications (real-time alerts)
- [x] Use Config Aggregator (multi-account visibility)
- [x] Implement automated remediation (reduce MTTR)
- [x] Review compliance dashboard weekly
- [x] Export compliance reports quarterly (audit evidence)

### ❌ Don't

- [ ] Disable Config Recorder (creates blind spots)
- [ ] Ignore non-compliant resources (technical debt accumulates)
- [ ] Record all resource types (cost optimization)
- [ ] Manually check compliance (use rules + automation)
- [ ] Store config data in public S3 buckets (security risk)
- [ ] Use overly permissive IAM roles for Config (least privilege)

---

## Compliance Mapping

| Standard | Config Rules Required | Status |
|----------|----------------------|--------|
| **CIS AWS Foundations** | 20+ rules (password policy, MFA, encryption, etc.) | ✅ Available as Conformance Pack |
| **PCI-DSS** | Encryption, access control, logging, monitoring | ✅ Available as Conformance Pack |
| **HIPAA** | Encryption at rest/transit, audit logs, access control | ✅ Custom Conformance Pack |
| **SOC 2** | Change tracking, access logging, encryption | ✅ Supported via Config + CloudTrail |
| **GDPR** | Data encryption, access controls, breach detection | ✅ Supported (custom rules) |
| **ISO 27001** | Security controls, change management, auditing | ✅ Supported (custom rules) |
| **NIST 800-53** | Configuration management, access control | ✅ Supported (custom rules) |

---

## Example Terraform Module

```terraform
module "aws_config" {
  source = "./modules/aws_config"
  
  env        = "production"
  project_id = "cerpac"
  
  # S3 bucket for config snapshots
  config_bucket_name = "production-cerpac-config-logs"
  
  # SNS topic for alerts
  sns_topic_arn = aws_sns_topic.security_alerts.arn
  
  # Enable specific managed rules
  enable_rules = {
    restricted_ssh                = true
    s3_bucket_public_read         = true
    rds_instance_public_access    = true
    encrypted_volumes             = true
    iam_password_policy           = true
    cloudtrail_enabled            = true
  }
  
  # Conformance packs
  conformance_packs = ["cis-aws-foundations-benchmark"]
  
  # Auto-remediation
  enable_auto_remediation = true
  
  # Multi-region
  all_regions = true
}
```

---

## Summary

AWS Config is essential for **continuous compliance monitoring** in production environments:

✅ **Automated Compliance**: 300+ pre-built rules for security and best practices  
✅ **Configuration History**: Track every change to every resource  
✅ **Multi-Account Support**: Centralized compliance across entire organization  
✅ **Automated Remediation**: Self-healing infrastructure via SSM/Lambda  
✅ **Audit Evidence**: Generate compliance reports for auditors  
✅ **Cost-Effective**: ~$130/month for comprehensive monitoring  

**Key Takeaway**: AWS Config answers "Is my infrastructure configured securely and compliantly?" by continuously evaluating resources against your policies. It's a cornerstone of cloud governance and should be enabled in all production environments.

---

**Last Updated**: January 11, 2026  
**Maintained By**: Security Team  
**Review Cycle**: Quarterly  
**Related Docs**: 
- [CloudTrail](./cloud_trail.md) - Audit logging
- [GuardDuty](./guardduty_in_architecture.md) - Threat detection
- [Security Hub](./aws-security-hub-standards.md) - Centralized security

