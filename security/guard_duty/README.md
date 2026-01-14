# AWS GuardDuty Terraform Module

Terraform module to enable and configure Amazon GuardDuty for intelligent threat detection using machine learning and threat intelligence.

## Overview

Amazon GuardDuty is a threat detection service that continuously monitors your AWS accounts and workloads for malicious activity and unauthorized behavior.

- **Machine Learning**: Analyzes billions of events to detect anomalies
- **Threat Intelligence**: Uses AWS and third-party threat feeds
- **Multi-Source Analysis**: CloudTrail, VPC Flow Logs, DNS logs, and more
- **Automated Detection**: No manual configuration of rules required
- **Real-Time Alerts**: Findings published within 15 minutes to 6 hours

## Module Structure

```
guard_duty/
├── main.tf       # GuardDuty detector and protection features
├── variables.tf  # Input variables
├── outputs.tf    # Module outputs (single 'guardduty' object)
└── README.md     # This file
```

## Features

✅ **Base Detector**: CloudTrail, VPC Flow Logs, DNS logs analysis  
✅ **S3 Data Events**: Monitor S3 object-level API calls for suspicious activity  
   - *AWS Console: Protection Plans → S3 Protection*  
✅ **EKS Protection**: Kubernetes audit log analysis  
   - *AWS Console: Protection Plans → EKS Protection*  
✅ **RDS Protection**: Database login activity monitoring  
   - *AWS Console: Protection Plans → RDS Protection*  
✅ **Lambda Protection**: Serverless function threat detection  
   - *AWS Console: Protection Plans → Lambda Protection*  
✅ **Runtime Monitoring**: EKS/ECS Fargate (ONLY) runtime behavior analysis  
   - *AWS Console: Protection Plans → Runtime Monitoring*
   - ⚠️ **NOT supported for ECS EC2 launch type** - use EBS Malware Protection instead  

### Malware Protection (3 Types)

GuardDuty provides three distinct malware protection capabilities:

1. **EC2/EBS Malware Protection** (`enable_ebs_malware_protection`)
   - **What**: GuardDuty-initiated scans of EBS volumes attached to EC2 instances
   - **When**: Triggered automatically when suspicious activity is detected
   - **Cost**: $0.10/GB scanned (only when triggered)
   - **AWS Console**: Protection Plans → Malware Protection → EC2
   - **Status**: ✅ Fully supported by this module

2. **S3 Malware Scanning** (`enable_s3_malware_protection`)
   - **What**: Scans new files uploaded to S3 buckets for malware
   - **When**: Real-time scanning of new uploads to configured buckets
   - **Cost**: Varies by usage (pay per scan)
   - **AWS Console**: Protection Plans → Malware Protection → S3
   - **Status**: ⚠️ NOT supported via Terraform `aws_guardduty_detector_feature`
   - **Note**: Must be configured manually in AWS Console - the variable `enable_s3_malware_protection` is kept for future compatibility but currently has no effect

3. **AWS Backup Malware Scanning** (Not yet supported)
   - **What**: Scans AWS Backup recovery points for malware
   - **When**: Automatic scans or on-demand
   - **Cost**: Varies by usage
   - **AWS Console**: Protection Plans → Malware Protection → AWS Backup
   - **Status**: ❌ Not yet available via Terraform (configure manually in console)

✅ **Configurable Frequency**: 15 minutes to 6 hours finding publication  

## Prerequisites

- AWS account with GuardDuty permissions
- (Optional) EKS clusters for EKS protection
- (Optional) RDS instances for RDS protection
- (Optional) Lambda functions for Lambda protection

## Usage

### Basic Configuration (Recommended for Production)

```terraform
module "guardduty" {
  source = "../../modules/security/guard_duty"

  env        = "production"
  project_id = "cerpac"

  # Enable GuardDuty
  enable_guardduty = true

  # Finding publication frequency
  finding_publishing_frequency = "FIFTEEN_MINUTES"  # Real-time alerting

  # Core protection features
  # Protection Plans → S3 Protection
  enable_s3_data_events = true   # Monitor S3 access patterns
  
  # Protection Plans → Malware Protection → EC2
  enable_ebs_malware_protection = true   # Scan EBS volumes for malware
  
  # Protection Plans → RDS Protection
  enable_rds_protection = true   # Monitor database logins
  
  # Protection Plans → Lambda Protection
  enable_lambda_protection = true   # Monitor Lambda network activity

  # Protection Plans → EKS Protection (only if you have EKS clusters)
  enable_eks_audit_logs = false

  # Protection Plans → Malware Protection → S3
  enable_s3_malware_protection = false  # Additional cost - enable if needed

  # Protection Plans → Runtime Monitoring (only if you have EKS/ECS Fargate/EC2)
  enable_runtime_monitoring = false  # Base feature - enables runtime monitoring capability
  enable_eks_runtime_agent  = false  # Auto-deploy agent to EKS (requires runtime_monitoring = true)
  
  # Note: ECS Fargate and EC2 agents must be enabled manually in AWS Console

  tags = {
    ManagedBy   = "Terraform"
    CostCenter  = "Security"
    Compliance  = "Required"
  }
}
```

### Minimal Configuration (Development/Testing)

```terraform
module "guardduty" {
  source = "../../modules/security/guard_duty"

  env        = "development"
  project_id = "my-project"

  # Basic GuardDuty only
  enable_guardduty = true

  # Longer frequency for cost savings
  finding_publishing_frequency = "SIX_HOURS"

  # Disable all optional features for cost savings
  # Protection Plans → S3 Protection
  enable_s3_data_events = false
  
  # Protection Plans → Malware Protection → EC2
  enable_ebs_malware_protection = false
  
  # Protection Plans → Malware Protection → S3
  enable_s3_malware_protection = false
  
  # Protection Plans → RDS Protection
  enable_rds_protection = false
  
  # Protection Plans → Lambda Protection
  enable_lambda_protection = false
  
  # Protection Plans → EKS Protection
  enable_eks_audit_logs = false
  
  # Protection Plans → Runtime Monitoring
  enable_runtime_monitoring = false  # Base feature
  enable_eks_runtime_agent  = false  # EKS agent deployment

  tags = {
    Environment = "dev"
  }
}
```

### Full Protection (High Security Environment)

```terraform
module "guardduty" {
  source = "../../modules/security/guard_duty"

  env        = "production"
  project_id = "cerpac"

  enable_guardduty             = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  # Enable all protection plans
  # Protection Plans → S3 Protection
  enable_s3_data_events = true   # Monitor S3 access patterns
  
  # Protection Plans → EKS Protection (only if you have EKS clusters)
  enable_eks_audit_logs = true
  
  # Protection Plans → RDS Protection
  enable_rds_protection = true   # Monitor database login attempts
  
  # Protection Plans → Lambda Protection
  enable_lambda_protection = true   # Monitor Lambda network activity
  
  # Protection Plans → Malware Protection → EC2
  enable_ebs_malware_protection = true   # Scan EBS volumes for malware
  
  # Protection Plans → Malware Protection → S3
  # Note: S3 malware scanning must be configured manually in AWS Console
  # The variable below has no effect currently (kept for future compatibility)
  enable_s3_malware_protection = false   # Not supported via Terraform
  
  # Protection Plans → Runtime Monitoring (only if you have EKS/ECS Fargate)
  enable_runtime_monitoring = true   # Enable base runtime monitoring feature
  enable_eks_runtime_agent  = true   # Auto-deploy agent to EKS clusters (optional)
  
  # Note: ECS Fargate and EC2 agents must be enabled manually in AWS Console

  tags = {
    ManagedBy   = "Terraform"
    Compliance  = "SOC2-PCI-HIPAA"
    DataClass   = "HighSecurity"
  }
}
```

## Protection Plans Mapping

This table maps AWS Console Protection Plans to Terraform variables for easy reference:

| AWS Console Location | Terraform Variable | Feature Name | Status |
|---------------------|-------------------|--------------|--------|
| **Protection Plans → S3 Protection** | `enable_s3_data_events` | S3 Data Events | ✅ Supported |
| **Protection Plans → EKS Protection** | `enable_eks_audit_logs` | EKS Audit Logs | ✅ Supported |
| **Protection Plans → RDS Protection** | `enable_rds_protection` | RDS Login Events | ✅ Supported |
| **Protection Plans → Lambda Protection** | `enable_lambda_protection` | Lambda Network Logs | ✅ Supported |
| **Protection Plans → Runtime Monitoring** | `enable_runtime_monitoring` | Runtime Monitoring Base | ✅ Supported |
| **Protection Plans → Runtime Monitoring → EKS** | `enable_eks_runtime_agent` | EKS Automated Agent | ✅ Supported (requires runtime_monitoring) |
| **Protection Plans → Runtime Monitoring → ECS Fargate** | Manual | ECS Fargate Agent | ⚠️ Manual configuration in console required |
| **Protection Plans → Runtime Monitoring → EC2** | Manual | EC2 Agent | ⚠️ Manual configuration in console required |
| **Protection Plans → Malware Protection → EC2** | `enable_ebs_malware_protection` | EBS Malware Scanning | ✅ Supported |
| **Protection Plans → Malware Protection → S3** | `enable_s3_malware_protection` | S3 Malware Scanning | ⚠️ Not available via `aws_guardduty_detector_feature` |
| **Protection Plans → Malware Protection → AWS Backup** | N/A | AWS Backup Scanning | ❌ Not available via Terraform |

**Important Notes**: 
- Setting `enable_runtime_monitoring = true` automatically enables EKS Runtime Monitoring as a sub-feature
- ECS Fargate runtime monitoring is automatically included with the main `RUNTIME_MONITORING` feature (no separate toggle)
- ⚠️ **Runtime Monitoring is ONLY supported for ECS Fargate** (serverless), NOT for ECS EC2 launch type
- For ECS tasks running on EC2 instances, use `enable_ebs_malware_protection` instead
- ⚠️ **S3 Malware Scanning is NOT available** via Terraform `aws_guardduty_detector_feature` - must configure manually in AWS Console

## Important: Feature Toggle Behavior

### How Feature Disabling Works

⚠️ **CRITICAL**: When you disable a GuardDuty feature (e.g., set `enable_s3_data_events = false`), this module **explicitly sets the feature status to DISABLED** in AWS.

**Why this matters:**

Previously enabled features don't automatically turn off when you remove Terraform resources. This module handles this correctly by:

1. **Always creating** the feature resource when GuardDuty is enabled
2. **Explicitly setting** `status = "ENABLED"` or `status = "DISABLED"` based on variables
3. **Ensuring** features are properly disabled in AWS Console when you set variables to `false`

### Example: Disabling S3 Protection

```terraform
# Initial configuration (S3 Protection enabled)
module "guardduty" {
  source = "../../modules/security/guard_duty"
  
  enable_s3_data_events = true  # S3 Protection ON
}
```

After applying, you'll see in AWS Console:
```
S3 Protection: ENABLED ✅
```

Now disable it:

```terraform
# Updated configuration (S3 Protection disabled)
module "guardduty" {
  source = "../../modules/security/guard_duty"
  
  enable_s3_data_events = false  # S3 Protection OFF
}
```

After running `terraform apply`, you'll see in AWS Console:
```
S3 Protection: DISABLED ❌
```

### What Happens Behind the Scenes

**Before the fix** (incorrect behavior):
- Setting `enable_s3_data_events = false` would **not create** the resource
- Previously enabled features would **remain enabled** in AWS
- Console would still show "S3 Protection: ENABLED" ❌

**After the fix** (correct behavior):
- Setting `enable_s3_data_events = false` **creates** the resource with `status = "DISABLED"`
- Feature is **explicitly disabled** in AWS
- Console correctly shows "S3 Protection: DISABLED" ✅

### Verification Steps

After disabling a feature:

1. Run `terraform apply` to update the configuration
2. Wait 1-2 minutes for AWS to process the change
3. Check AWS Console → GuardDuty → Protection plans
4. Verify the feature shows "DISABLED"

If you still see "ENABLED" after 5 minutes:
- Check Terraform state: `terraform state list | grep guardduty`
- Verify variable value: `terraform console` → `var.enable_s3_data_events`
- Force refresh: `terraform refresh` then `terraform apply`

## Understanding S3 Protection Options

⚠️ **IMPORTANT**: GuardDuty has TWO different S3 protection features that serve different purposes:

### 1. S3 Data Events (`enable_s3_data_events`)

**AWS Console**: Protection Plans → S3 Protection

**What it does**: Monitors **WHO** accessed S3 and **WHAT** they did
- Tracks S3 API calls (GetObject, PutObject, DeleteObject, etc.)
- Analyzes access patterns for anomalies
- Detects unusual download volumes or suspicious access times

**Example threats detected**:
- An EC2 instance suddenly downloading 100GB of data
- S3 access from a malicious IP address
- Unusual access patterns (e.g., accessing thousands of objects rapidly)
- Data exfiltration attempts

**Cost**: ~$0.20/GB of S3 data analyzed  
**Variable**: `enable_s3_data_events = true/false`  
**AWS Console**: GuardDuty → Data sources → S3 logs

### 2. S3 Malware Scanning (`enable_s3_malware_protection`)

**AWS Console**: Protection Plans → Malware Protection → S3

⚠️ **IMPORTANT**: S3 Malware Scanning is NOT currently supported via Terraform's `aws_guardduty_detector_feature` resource. It must be configured manually in the AWS Console.

**What it does**: Scans **FILE CONTENTS** for malware
- Analyzes the actual bytes of uploaded files
- Checks against malware signature databases
- Scans for trojans, ransomware, viruses, malicious scripts

**Example threats detected**:
- User uploads a file containing ransomware
- Malicious executable uploaded to S3
- JavaScript file with embedded malware
- PDF with embedded exploit code

**Cost**: Varies by usage (pay per scan)  
**Variable**: `enable_s3_malware_protection = true/false` (currently has no effect - kept for future compatibility)  
**AWS Console**: GuardDuty → Malware Protection → S3  
**Status**: Must be manually configured in AWS Console

### Comparison Table

| Feature | S3 Data Events | S3 Malware Scanning |
|---------|----------------|---------------------|
| **Analyzes** | API access patterns | File contents |
| **Detects** | Unusual access behavior | Malware in files |
| **Example** | "Someone downloaded 1000 files" | "File contains virus" |
| **Terraform Support** | ✅ Fully supported | ⚠️ Manual configuration only |
| **Use Case** | Insider threats, data exfiltration | Malware uploads, compromised files |
| **Cost** | $0.20/GB analyzed | Per-scan pricing |
| **Setup** | Enable feature (done) | Enable + configure buckets |

### When to Use Each

**Enable S3 Data Events if**:
- You need to detect data exfiltration
- You want to monitor access patterns
- You have compliance requirements for access logging
- You want to detect compromised IAM credentials

**Enable S3 Malware Scanning if**:
- Users upload files to S3 (file sharing, user-generated content)
- You store downloaded files from external sources
- You need to prevent malware distribution
- You have compliance requirements for malware scanning

**Best Practice**: Enable BOTH for comprehensive S3 protection 🛡️

### Configuration Example

```terraform
module "guardduty" {
  source = "../../modules/security/guard_duty"

  env        = "production"
  project_id = "cerpac"

  # Protection Plans → S3 Protection
  # Monitor S3 access patterns (WHO did WHAT)
  enable_s3_data_events = true

  # Protection Plans → Malware Protection → S3
  # ⚠️ Note: S3 malware scanning must be configured manually in AWS Console
  # The variable below currently has no effect (kept for future compatibility)
  # enable_s3_malware_protection = false  # Not supported via Terraform

  # Other features...
}
```

### Manual Setup for S3 Malware Scanning

⚠️ **S3 Malware Scanning cannot be configured via Terraform** at this time. To enable it:

1. **Navigate to AWS Console**:
   - GuardDuty → Malware Protection → S3 → Configure
   
2. **Configure which buckets to scan**:
   - Select buckets and optionally specific prefixes
   
3. **Set up notifications** (optional but recommended):
   - Create EventBridge rule for malware findings
   - Send alerts to SNS, Slack, or email

4. **Define remediation actions** (optional):
   - Auto-quarantine infected files
   - Move to isolated bucket
   - Delete malicious uploads

## Understanding Runtime Monitoring: ECS Fargate vs ECS EC2

⚠️ **CRITICAL**: Runtime Monitoring has different support depending on your ECS launch type.

### What Runtime Monitoring Does

Runtime Monitoring requires TWO things:
1. **Enable the feature** - Done via Terraform (`enable_runtime_monitoring = true`)
2. **Deploy the security agent** - Must be configured per platform

### Automated Agent Configuration

When you enable Runtime Monitoring, you'll see in the AWS Console:

```
Runtime Monitoring configuration
├── Runtime Monitoring Status: Enabled ✅
└── Automated agent configuration:
    ├── Amazon EKS: Enabled ✅ (via EKS_RUNTIME_MONITORING)
    ├── AWS Fargate (ECS only): Not enabled ⚠️ (manual configuration required)
    └── Amazon EC2: Not enabled ⚠️ (manual configuration required)
```

### What This Module Configures

| Platform | Terraform Support | Status in Console | Action Required |
|----------|------------------|-------------------|-----------------|
| **Base Runtime Monitoring** | ✅ Fully supported | "Runtime Monitoring Status: Enabled" | None - automated |
| **Amazon EKS** | ✅ Fully supported | "Automated agent configuration for Amazon EKS is enabled" | None - automated |
| **AWS Fargate (ECS)** | ⚠️ Manual only | "Automated agent configuration for AWS Fargate (ECS only) is not enabled" | Manual enable in console |
| **Amazon EC2** | ⚠️ Manual only | "Automated agent configuration for Amazon EC2 is not enabled" | Manual enable in console |

### ECS Fargate (Serverless) - ⚠️ MANUAL CONFIGURATION REQUIRED

**What**: AWS-managed serverless container platform  
**Runtime Monitoring**: ✅ Supported but requires manual agent configuration  
**Terraform**: Enables Runtime Monitoring feature, but agent deployment must be configured manually  

**Steps after enabling `enable_runtime_monitoring = true`**:
1. Go to AWS Console → GuardDuty → Runtime Monitoring → Configuration
2. Under "Automated agent configuration"
3. Find "AWS Fargate (ECS only)"
4. Click "Enable" button
5. GuardDuty will automatically inject agent into new Fargate tasks

**Why manual?**  
There's no Terraform resource available to enable ECS Fargate automated agent configuration via `aws_guardduty_detector_feature`.

**Example Configuration**:
```terraform
module "guardduty" {
  source = "../../modules/security/guard_duty"

  env        = "production"
  project_id = "my-app"

  # ✅ This enables Runtime Monitoring feature
  enable_runtime_monitoring = true
  
  # ⚠️ Manual step required: Enable ECS Fargate agent in console
}
```

### ECS EC2 (Container Instances) - ❌ NOT SUPPORTED

**What**: ECS tasks running on EC2 instances you manage  
**Runtime Monitoring**: ❌ NOT supported (agent cannot be injected)  
**Alternative**: Use EBS Malware Protection instead  
**Variable**: `enable_ebs_malware_protection = true`  
**AWS Console**: Protection Plans → Malware Protection → EC2  

**Example Configuration**:
```terraform
module "guardduty" {
  source = "../../modules/security/guard_duty"

  env        = "production"
  project_id = "my-app"

  # ❌ Runtime Monitoring doesn't work for ECS EC2
  enable_runtime_monitoring = false

  # ✅ Use EBS Malware Protection instead
  enable_ebs_malware_protection = true
}
```

### EKS (Kubernetes) - ✅ FULLY AUTOMATED

**What**: Amazon Elastic Kubernetes Service  
**Runtime Monitoring**: ✅ Fully supported and automated via Terraform  
**Terraform**: Both feature and agent configuration automated  

**Example Configuration**:
```terraform
module "guardduty" {
  source = "../../modules/security/guard_duty"

  env        = "production"
  project_id = "my-app"

  # ✅ Fully automated - both feature and agent deployment
  enable_runtime_monitoring = true
}
```

**What happens**:
1. Terraform enables `RUNTIME_MONITORING` feature
2. Terraform enables `EKS_RUNTIME_MONITORING` feature (automated agent configuration)
3. GuardDuty automatically deploys agent to all EKS clusters
4. No manual steps required! ✅

### Amazon EC2 Instances - ⚠️ MANUAL CONFIGURATION REQUIRED

**What**: Standalone EC2 instances (not ECS)  
**Runtime Monitoring**: ✅ Supported but requires manual agent configuration  
**Terraform**: Enables Runtime Monitoring feature, but agent deployment must be configured manually  

**Steps after enabling `enable_runtime_monitoring = true`**:
1. Go to AWS Console → GuardDuty → Runtime Monitoring → Configuration
2. Under "Automated agent configuration"
3. Find "Amazon EC2"
4. Click "Enable" button
5. GuardDuty will deploy agent to EC2 instances via AWS Systems Manager

**Why manual?**  
There's no Terraform resource available to enable EC2 automated agent configuration via `aws_guardduty_detector_feature`.

### Why the Difference?

| Aspect | EKS | ECS Fargate | ECS EC2 | EC2 Instances |
|--------|-----|-------------|---------|---------------|
| **Infrastructure** | AWS-managed K8s | AWS-managed serverless | You manage instances | You manage instances |
| **Terraform Support** | ✅ Full | ⚠️ Feature only | ❌ None | ⚠️ Feature only |
| **Agent Deployment** | Automated via Terraform | Manual console config | Not supported | Manual console config |
| **Protection Method** | Runtime monitoring | Runtime monitoring | EBS volume scanning | Runtime monitoring |
| **Manual Steps** | None | Enable in console | Use EBS protection | Enable in console |

### Quick Decision Guide

**You have EKS clusters?**  
→ Enable `enable_runtime_monitoring = true`  
→ ✅ Fully automated - no manual steps!

**You have ECS Fargate tasks?**  
→ Enable `enable_runtime_monitoring = true`  
→ ⚠️ Then manually enable agent in AWS Console:
  - GuardDuty → Runtime Monitoring → Configuration
  - Automated agent configuration → AWS Fargate (ECS only) → Enable

**You have ECS tasks on EC2 instances?**  
→ Enable `enable_ebs_malware_protection = true`  
→ DO NOT enable `enable_runtime_monitoring` (it won't work)

**You have standalone EC2 instances?**  
→ Enable `enable_runtime_monitoring = true`  
→ ⚠️ Then manually enable agent in AWS Console:
  - GuardDuty → Runtime Monitoring → Configuration
  - Automated agent configuration → Amazon EC2 → Enable

**You have a mix?**  
→ Enable both:
```terraform
enable_runtime_monitoring     = true  # For EKS, ECS Fargate, EC2 instances
enable_ebs_malware_protection = true  # For ECS EC2 launch type
```
→ ⚠️ Manual configuration required for:
  - ECS Fargate agent (enable in console)
  - EC2 instance agent (enable in console)
→ ✅ EKS agent is fully automated!

## Outputs

This module provides a single comprehensive `guardduty` output object:

```terraform
output "guardduty" {
  value = {
    # Detector - Core GuardDuty service
    detector = {
      id                           = "abc123..."
      arn                          = "arn:aws:guardduty:eu-west-2:123456789012:detector/abc123"
      account_id                   = "123456789012"
      finding_publishing_frequency = "FIFTEEN_MINUTES"
      status                       = "ENABLED"
    }

    # Data Sources - What GuardDuty monitors
    data_sources = {
      cloudtrail       = true   # API call monitoring
      vpc_flow_logs    = true   # Network traffic analysis
      dns_logs         = true   # DNS query analysis
      s3_logs          = true   # S3 data event monitoring
      kubernetes_logs  = false  # EKS audit logs (if enabled)
      malware_scanning = true   # EBS malware scanning
    }

    # Protection Features - Advanced capabilities
    features = {
      s3_data_events         = false
      eks_audit_logs         = false
      rds_login_events       = true
      lambda_network_logs    = true
      ebs_malware_protection = false
    }

    # Configuration Summary
    summary = {
      module_enabled             = true
      environment                = "production"
      project_id                 = "cerpac"
      total_features_enabled     = 3
      total_data_sources_enabled = 6
    }
  }
}
```

### Using Outputs

```terraform
module "guardduty" {
  source = "../../modules/security/guard_duty"
  # ...configuration...
}

# Access detector ID
output "guardduty_detector_id" {
  value = module.guardduty.guardduty.detector.id
}

# Use in EventBridge rules
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "guardduty-high-severity-findings"
  description = "Capture high severity GuardDuty findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [7, 8, 9]  # High severity only
    }
  })
}

resource "aws_cloudwatch_event_target" "sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts.arn
}

# Reference in Security Hub
resource "aws_securityhub_product_subscription" "guardduty" {
  product_arn = "arn:aws:securityhub:${data.aws_region.current.name}::product/aws/guardduty"
  
  depends_on = [module.guardduty]
}
```

## Cost Estimate

### Typical Production Environment

| Component | Volume | Unit Cost | Monthly Cost |
|-----------|--------|-----------|--------------|
| **CloudTrail Analysis** | 1M events | $4.40/M events | $4.40 |
| **VPC Flow Logs Analysis** | 50 GB | $1.18/GB | $59.00 |
| **DNS Logs Analysis** | 5M queries | $0.40/M queries | $2.00 |
| **S3 Protection** | 100 GB | $0.20/GB | $20.00 |
| **RDS Protection** | Included | Free | $0.00 |
| **Lambda Protection** | Included | Free | $0.00 |
| **EKS Audit Logs** | 10 GB | $0.012/GB | $0.12 |
| **EBS Malware Scanning** | 5 scans × 20 GB | $0.10/GB | $10.00 |
| **TOTAL** | | | **~$95.52/month** |

### Cost Optimization Tips

1. **Adjust Finding Frequency**: Use `SIX_HOURS` in dev/test environments
   ```terraform
   finding_publishing_frequency = "SIX_HOURS"
   ```

2. **Disable Unused Features**: Only enable features for resources you use
   ```terraform
   enable_eks_protection = false  # If no EKS clusters
   enable_s3_data_events = false  # If basic S3 protection is sufficient
   ```

3. **Use Trusted IP Lists**: Exclude known safe IPs from analysis
   ```terraform
   resource "aws_guardduty_ipset" "trusted_ips" {
     activate    = true
     detector_id = module.guardduty.guardduty.detector.id
     format      = "TXT"
     location    = "s3://my-bucket/trusted-ips.txt"
     name        = "TrustedIPs"
   }
   ```

4. **Use Threat Intel Lists**: Suppress findings for known false positives
   ```terraform
   resource "aws_guardduty_threatintelset" "custom_threats" {
     activate    = true
     detector_id = module.guardduty.guardduty.detector.id
     format      = "TXT"
     location    = "s3://my-bucket/threat-intel.txt"
     name        = "CustomThreats"
   }
   ```

## Threat Detection Capabilities

### What GuardDuty Detects

| Category | Threat Types | Example Findings |
|----------|-------------|------------------|
| **Reconnaissance** | Port scanning, unusual API calls | `Recon:EC2/PortProbeUnprotectedPort` |
| **Instance Compromise** | Malware, backdoors, crypto mining | `CryptoCurrency:EC2/BitcoinTool.B!DNS` |
| **Account Compromise** | Stolen credentials, unusual login | `UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration` |
| **Bucket Compromise** | Data exfiltration, policy changes | `Exfiltration:S3/ObjectRead.Unusual` |
| **Malware** | Trojan, rootkit, ransomware | `Trojan:EC2/BlackholeTraffic` |
| **Backdoor** | C2 communication, unusual protocols | `Backdoor:EC2/C&CActivity.B!DNS` |

### Finding Severity Levels

| Severity | Score | Description | Action |
|----------|-------|-------------|--------|
| **Low** | 0.1 - 3.9 | Suspicious activity | Review periodically |
| **Medium** | 4.0 - 6.9 | Potentially malicious | Investigate within 24 hours |
| **High** | 7.0 - 8.9 | Malicious activity | Investigate immediately |
| **Critical** | 9.0 | Active threat | Respond immediately |

## Integration with Security Services

### 1. Amazon SNS (Real-Time Alerts)

```terraform
# SNS topic for GuardDuty findings
resource "aws_sns_topic" "guardduty_alerts" {
  name = "guardduty-high-severity-alerts"
}

resource "aws_sns_topic_subscription" "security_team" {
  topic_arn = aws_sns_topic.guardduty_alerts.arn
  protocol  = "email"
  endpoint  = "security@company.com"
}

# EventBridge rule to send findings to SNS
resource "aws_cloudwatch_event_rule" "guardduty_high_severity" {
  name        = "guardduty-high-severity-findings"
  description = "Alert on high severity GuardDuty findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [
        { numeric = [">=", 7] }  # High and Critical findings only
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_high_severity.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.guardduty_alerts.arn
}
```

### 2. AWS Security Hub

```terraform
# Enable Security Hub
resource "aws_securityhub_account" "main" {}

# Subscribe to GuardDuty findings in Security Hub
resource "aws_securityhub_product_subscription" "guardduty" {
  product_arn = "arn:aws:securityhub:${data.aws_region.current.name}::product/aws/guardduty"
  
  depends_on = [
    aws_securityhub_account.main,
    module.guardduty
  ]
}
```

### 3. AWS Lambda (Automated Response)

```terraform
# Lambda function for automated response
resource "aws_lambda_function" "guardduty_response" {
  filename      = "guardduty_response.zip"
  function_name = "guardduty-automated-response"
  role          = aws_iam_role.lambda_guardduty.arn
  handler       = "index.handler"
  runtime       = "python3.11"

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.guardduty_alerts.arn
    }
  }
}

# EventBridge rule to trigger Lambda
resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.guardduty_high_severity.name
  target_id = "TriggerLambda"
  arn       = aws_lambda_function.guardduty_response.arn
}
```

### 4. Amazon Detective (Investigation)

```terraform
# Enable Detective for forensic investigation
resource "aws_detective_graph" "main" {
  tags = {
    Name = "production-detective"
  }
  
  depends_on = [module.guardduty]
}

# Detective automatically ingests GuardDuty findings
```

## Viewing GuardDuty Findings

### AWS Console

1. Navigate to **GuardDuty** → **Findings**
2. Filter by severity, threat type, or resource
3. Click finding for detailed analysis

### AWS CLI

```bash
# List all findings
aws guardduty list-findings \
  --detector-id abc123... \
  --finding-criteria '{"Criterion":{"severity":{"Gte":7}}}'

# Get finding details
aws guardduty get-findings \
  --detector-id abc123... \
  --finding-ids finding-id-123
```

### CloudWatch Logs Insights

```sql
# Query GuardDuty findings (if exported to CloudWatch)
fields @timestamp, detail.severity, detail.type, detail.resource.instanceDetails.instanceId
| filter detail.severity >= 7
| sort @timestamp desc
| limit 100
```

## Responding to Findings

### Example: Compromised EC2 Instance

**Finding**: `Backdoor:EC2/C&CActivity.B!DNS` (Severity: 8.0)

**Immediate Actions**:
1. Isolate the instance (change security group)
2. Snapshot EBS volumes for forensics
3. Disable instance metadata service access
4. Rotate credentials used by the instance

**Investigation**:
1. Review CloudTrail logs for API calls from the instance
2. Check VPC Flow Logs for network connections
3. Scan EBS volumes with GuardDuty malware protection
4. Use Amazon Detective for timeline analysis

**Remediation**:
```bash
# Isolate instance (change security group to deny all)
aws ec2 modify-instance-attribute \
  --instance-id i-0123456789abcdef \
  --groups sg-quarantine

# Create forensic snapshot
aws ec2 create-snapshot \
  --volume-id vol-0123456789abcdef \
  --description "Forensic snapshot - GuardDuty finding"

# Stop instance
aws ec2 stop-instances --instance-ids i-0123456789abcdef
```

### Example: S3 Data Exfiltration

**Finding**: `Exfiltration:S3/ObjectRead.Unusual` (Severity: 7.5)

**Immediate Actions**:
1. Review S3 access logs
2. Check IAM credentials used
3. Enable S3 Object Lock if not already enabled
4. Rotate compromised credentials

**Investigation**:
```bash
# Review S3 access logs
aws s3api get-bucket-logging --bucket my-bucket

# List recent access events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=my-bucket \
  --max-results 50
```

## Troubleshooting

### GuardDuty Not Detecting Threats

**Issue**: No findings appearing

**Possible Causes**:
1. Detector not enabled
2. No actual threats in environment (good!)
3. Trusted IP list excluding legitimate threats

**Verification**:
```bash
# Check detector status
aws guardduty get-detector --detector-id abc123...

# List all findings (even low severity)
aws guardduty list-findings --detector-id abc123...
```

### High False Positive Rate

**Issue**: Too many low-severity findings

**Solutions**:
1. Add trusted IPs to suppression list
2. Use finding suppression rules
3. Archive low-severity findings

```terraform
# Suppress specific finding types
resource "aws_guardduty_filter" "suppress_low_severity" {
  detector_id = module.guardduty.guardduty.detector.id
  name        = "suppress-low-severity"
  action      = "ARCHIVE"
  rank        = 1

  finding_criteria {
    criterion {
      field  = "severity"
      less_than = "4"
    }
  }
}
```

### Missing EKS/RDS Findings

**Issue**: No findings for EKS/RDS

**Possible Causes**:
1. Protection not enabled
2. No EKS clusters or RDS instances in account
3. No malicious activity detected

**Fix**: Verify protection is enabled
```terraform
enable_eks_protection = true
enable_rds_protection = true
```

## Best Practices

### ✅ Recommended

- [x] Enable GuardDuty in all regions
- [x] Use `FIFTEEN_MINUTES` frequency in production
- [x] Enable S3, RDS, and Lambda protection
- [x] Set up SNS alerts for high-severity findings
- [x] Integrate with Security Hub for centralized view
- [x] Create automated response playbooks
- [x] Review findings weekly
- [x] Archive false positives to reduce noise

### ❌ Avoid

- [ ] Disabling GuardDuty to save costs (security > cost)
- [ ] Ignoring medium-severity findings
- [ ] Using only CloudWatch Events without SNS
- [ ] Not investigating high-severity findings
- [ ] Enabling all features without understanding costs
- [ ] Not documenting suppression rules

## Compliance Mapping

| Standard | Requirement | Status |
|----------|-------------|--------|
| **CIS AWS Foundations** | Threat detection enabled | ✅ Met |
| **PCI-DSS 10.6** | Review logs for anomalies | ✅ Met |
| **HIPAA 164.308(a)(1)** | Threat and vulnerability analysis | ✅ Met |
| **SOC 2 CC7.2** | System monitoring | ✅ Met |
| **NIST 800-53 SI-4** | System monitoring | ✅ Met |
| **ISO 27001 A.12.4.1** | Event logging and monitoring | ✅ Met |

## Variables Reference

| Variable | Type | Default | Description | AWS Console |
|----------|------|---------|-------------|-------------|
| `enable_guardduty` | bool | `true` | Enable/disable GuardDuty | - |
| `env` | string | Required | Environment name | - |
| `project_id` | string | Required | Project identifier | - |
| `tags` | map(string) | `{}` | Additional tags | - |
| `finding_publishing_frequency` | string | `FIFTEEN_MINUTES` | Finding publication frequency | - |
| `enable_s3_data_events` | bool | `true` | Enable S3 data events monitoring | Protection Plans → S3 Protection |
| `enable_eks_audit_logs` | bool | `false` | Enable EKS audit logs monitoring | Protection Plans → EKS Protection |
| `enable_rds_protection` | bool | `true` | Enable RDS login activity monitoring | Protection Plans → RDS Protection |
| `enable_lambda_protection` | bool | `true` | Enable Lambda network monitoring | Protection Plans → Lambda Protection |
| `enable_ebs_malware_protection` | bool | `true` | Enable EC2/EBS malware scanning | Protection Plans → Malware Protection → EC2 |
| `enable_s3_malware_protection` | bool | `false` | ⚠️ Not supported - must configure manually in AWS Console | Protection Plans → Malware Protection → S3 |
| `enable_runtime_monitoring` | bool | `false` | Enable base runtime monitoring feature | Protection Plans → Runtime Monitoring |
| `enable_eks_runtime_agent` | bool | `false` | Enable automated EKS agent deployment (requires runtime_monitoring) | Protection Plans → Runtime Monitoring → EKS |

## Related Modules

- **CloudTrail**: API audit logging
- **AWS Config**: Configuration compliance
- **Security Hub**: Centralized security findings
- **Amazon Detective**: Security investigation

## Support

For issues or questions:
- Internal: Contact Security Team
- Documentation: See [AWS GuardDuty Documentation](https://docs.aws.amazon.com/guardduty/)

---

**Last Updated**: January 11, 2026  
**Version**: 1.0.0  
**Maintained By**: Security Team

