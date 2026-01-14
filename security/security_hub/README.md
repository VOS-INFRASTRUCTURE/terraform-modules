# AWS Security Hub Terraform Module

Centralized security posture management and compliance monitoring with AWS Security Hub.

## Overview

This module provides security monitoring and compliance management by configuring:

- **AWS Security Hub**: Centralized security findings and compliance management
- **Security Standards**: AWS Foundational, CIS Benchmark v5.0, Resource Tagging
- **EventBridge Integration**: Routes findings to external SNS topic for alerting
- **GuardDuty Integration**: Threat detection findings aggregation
- **AWS Config Dependency**: Required for standards compliance checks

**Note**: This module does NOT create SNS topics, email subscriptions, or Slack integrations.
Use the `security_notification` module separately to configure alerting channels.

## Module Structure

```
security_hub/
├── main.tf                          # Module entry point and data sources
├── security_hub.tf                  # Security Hub enablement and standards
├── security_hub_alerting.tf         # EventBridge rules for findings routing
├── variables.tf                     # Input variables
├── outputs.tf                       # Module outputs
└── README.md                        # This file
```

## Features

✅ **Security Hub Standards**: AWS Foundational, CIS Benchmark v5.0, Resource Tagging  
✅ **GuardDuty Integration**: Threat detection findings aggregation  
✅ **EventBridge Routing**: Automatic findings forwarding to external SNS topic  
✅ **Standards Compliance**: Continuous compliance monitoring  
✅ **Multi-Standard Support**: Enable/disable standards independently  
✅ **External Alerting**: Integrates with security_notification module for email/Slack  

## Prerequisites

- **AWS Config enabled** (required for Security Hub standards - many controls use Config Rules)
- **security_notification module** (for SNS topic and alerting setup)
- (Optional) GuardDuty enabled for threat detection

**Important**: AWS Security Hub standards (AWS Foundational Security Best Practices, CIS Benchmark, Resource Tagging) rely heavily on AWS Config Rules to evaluate resource compliance. Without AWS Config enabled, many security controls will not function properly.

## Usage

### Basic Configuration (Security Hub with Email Alerts)

```terraform
# Step 1: Create notification infrastructure
module "security_alerts" {
  source = "../../modules/security/security_notification"

  env        = "production"
  project_id = "cerpac"

  # Enable email notifications
  enable_email_alerts  = true
  security_alert_email = "security@company.com"
}

# Step 2: Enable Security Hub and route findings to SNS
module "security_hub" {
  source = "../../modules/security/security_hub"

  env        = "production"
  project_id = "cerpac"

  # Enable Security Hub
  enable_security_hub = true

  # Enable specific standards
  enable_aws_foundational_standard = true
  enable_cis_standard              = true
  enable_resource_tagging_standard = false

  # Enable GuardDuty integration
  enable_guardduty_integration = true

  # Enable alerting (route findings to SNS topic)
  enable_security_alerting      = true
  security_alerts_sns_topic_arn = module.security_alerts.sns_topic_arn
}
```

### Full Configuration (with Email and Slack Integration)

```terraform
# Step 1: Create notification infrastructure with both email and Slack
module "security_alerts" {
  source = "../../modules/security/security_notification"

  env        = "production"
  project_id = "cerpac"

  # Enable email notifications
  enable_email_alerts  = true
  security_alert_email = "security@company.com"

  # Enable Slack notifications (HIGH/CRITICAL only)
  enable_slack_alerts        = true
  security_slack_webhook_url = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
}

# Step 2: Enable Security Hub with all standards
module "security_hub" {
  source = "../../modules/security/security_hub"

  env        = "production"
  project_id = "cerpac"

  # Enable Security Hub with all standards
  enable_security_hub              = true
  enable_aws_foundational_standard = true
  enable_cis_standard              = true
  enable_resource_tagging_standard = true

  # Enable GuardDuty integration
  enable_guardduty_integration = true

  # Route findings to SNS topic (which forwards to email and Slack)
  enable_security_alerting      = true
  security_alerts_sns_topic_arn = module.security_alerts.sns_topic_arn
}
```

### Full Configuration (with Beautiful HTML Emails via SES)

```terraform
# Step 1: Create notification infrastructure with SES email handler
module "security_alerts" {
  source = "../../modules/security/security_notification"

  env        = "production"
  project_id = "cerpac"

  # Enable beautiful HTML emails via Lambda + SES (HIGH/CRITICAL only)
  enable_email_alerts  = true
  enable_email_handler = true
  ses_from_email       = "security-alerts@company.com"  # Must be verified in SES
  ses_to_emails        = [
    "security-team@company.com",
    "oncall@company.com"
  ]

  # Optional: Also send to Slack
  enable_slack_alerts        = true
  security_slack_webhook_url = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
}

# Step 2: Enable Security Hub with all standards
module "security_hub" {
  source = "../../modules/security/security_hub"

  env        = "production"
  project_id = "cerpac"

  # Enable Security Hub with all standards
  enable_security_hub              = true
  enable_aws_foundational_standard = true
  enable_cis_standard              = true
  enable_resource_tagging_standard = true

  # Enable GuardDuty integration
  enable_guardduty_integration = true

  # Route findings to SNS topic
  enable_security_alerting      = true
  security_alerts_sns_topic_arn = module.security_alerts.sns_topic_arn
}
```

**Note**: Before using the email handler, you must:
1. Verify the sender email address in Amazon SES
2. If in SES sandbox, verify recipient email addresses too
3. Request production access for SES if sending to non-verified addresses

### Selective Standards (AWS Foundational Only)

```terraform
# Step 1: Create notification infrastructure
module "security_alerts" {
  source = "../../modules/security/security_notification"

  env        = "production"
  project_id = "cerpac"

  # Simple email alerts
  enable_email_alerts  = true
  security_alert_email = "security@company.com"
}

# Step 2: Enable Security Hub with only AWS Foundational standard
module "security_hub" {
  source = "../../modules/security/security_hub"

  env        = "production"
  project_id = "cerpac"

  # Enable Security Hub
  enable_security_hub = true

  # Enable only AWS Foundational standard
  enable_aws_foundational_standard = true
  enable_cis_standard              = false  # Disable CIS
  enable_resource_tagging_standard = false  # Disable tagging

  # Enable GuardDuty integration
  enable_guardduty_integration = true

  # Alerting
  enable_security_alerting      = true
  security_alerts_sns_topic_arn = module.security_alerts.sns_topic_arn
}
```

### Minimal Configuration (Security Hub Only, No Alarms)

```terraform
module "security_hub" {
  source = "../../modules/security/security_hub"

  env        = "production"
  project_id = "cerpac"

  # Enable Security Hub with minimal standards
  enable_security_hub              = true
  enable_aws_foundational_standard = true
  enable_cis_standard              = false
  enable_resource_tagging_standard = false

  # Disable GuardDuty integration if not using GuardDuty
  enable_guardduty_integration = false

  # Disable alerting completely
  enable_security_alerting      = false
  security_alerts_sns_topic_arn = ""  # Not needed when alerting disabled
}
```

## Architecture

### Data Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                      AWS Security Hub                               │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐ │
│  │ AWS Foundational │  │  CIS Benchmark   │  │  Resource Tags   │ │
│  │   Best Practices │  │     v5.0.0       │  │     Standard     │ │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘ │
│           │                     │                      │            │
│           └──────────┬──────────┴──────────┬───────────┘            │
│                      │ Requires            │                        │
│                      ▼                     │                        │
│           ┌─────────────────────┐          │                        │
│           │    AWS Config       │◀─────────┘                        │
│           │  (Config Rules)     │                                   │
│           └─────────────────────┘                                   │
│           Many standards use AWS Config Rules for compliance checks │
│                                                                     │
│  Integrations: GuardDuty, AWS Config, Inspector, IAM Analyzer      │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               │ Findings Imported
                               ▼
                    ┌────────────────────┐
                    │    EventBridge     │
                    │  (Security Hub)    │
                    └─────────┬──────────┘
                              │
                              ▼
    ┌──────────────────────────────────────▼────────────┐
    │              SNS Topic                            │
    │   (from security_notification module)             │
    └───────────────┬───────────────┬───────────────────┘
                    │               │
        ┌───────────┘               └──────────┐
        ▼                                      ▼
┌────────────────┐                  ┌──────────────────────┐
│     Email      │                  │  Lambda Normalizer   │
│  Subscription  │                  │  (Filter + Format)   │
│ (Basic or SES) │                  │  - HIGH/CRITICAL     │
└────────────────┘                  └──────────┬───────────┘
                                               │
                                               │ Only HIGH/CRITICAL
                                               ▼
                                    ┌─────────────────────┐
                                    │   Slack Channel     │
                                    │  #security-alerts   │
                                    └─────────────────────┘
```

**Module Separation**:
- **security_hub module** (this module): Security Hub + EventBridge routing
- **security_notification module** (separate): SNS topic + Email + Slack Lambda

## Outputs

This module provides a single comprehensive `security_hub` output object:

```terraform
output "security_hub" {
  value = {
    # Security Hub core service
    hub = {
      account_id = "123456789012"
      region     = "eu-west-2"
      enabled    = true
      
      standards = {
        aws_foundational = "arn:aws:securityhub:eu-west-2::standards/..."
        cis_benchmark    = "arn:aws:securityhub:eu-west-2::standards/..."
        resource_tagging = "arn:aws:securityhub:eu-west-2::standards/..."
      }
      
      products = {
        guardduty = "arn:aws:securityhub:eu-west-2::product/aws/guardduty"
      }
    }

    # Alerting infrastructure (EventBridge routing)
    alerting = {
      sns_topic_arn  = "arn:aws:sns:..."  # External SNS topic ARN
      sns_topic_name = "production-cerpac-security-alerts"
      
      eventbridge = {
        rule_name = "production-securityhub-findings"
        rule_arn  = "arn:aws:events:..."
      }
      
      # Note: SNS topic, Slack Lambda, and Email Lambda are managed by
      #       the security_notification module, not this module
    }

    # Configuration summary
    summary = {
      module_enabled            = true
      environment               = "production"
      project_id                = "cerpac"
      security_hub_enabled      = true
      security_alerting_enabled = true
      sns_topic_arn             = "arn:aws:sns:..."
      total_standards_enabled   = 2
    }
  }
}
```

### Using Outputs

```terraform
module "security_hub" {
  source = "../../modules/security/security_hub"
  # ...configuration...
}

# Get SNS topic for other integrations
output "security_alerts_topic" {
  value = module.security_hub.security_hub.alerting.sns_topic_arn
}

# Get alarm names for dashboards
output "critical_alarms" {
  value = [
    module.security_hub.security_hub.alarms.security.alarms.root_account_usage,
    module.security_hub.security_hub.alarms.security.alarms.cloudtrail_changes,
  ]
}

# Get Security Hub account info
output "security_hub_region" {
  value = module.security_hub.security_hub.hub.region
}
```


## Security Hub Standards

### 1. AWS Foundational Security Best Practices v1.0.0

Comprehensive security checks across all AWS services:
- IAM best practices
- S3 bucket security
- EC2 security configurations
- RDS encryption and backups
- Lambda function security
- And many more...

### 2. CIS AWS Foundations Benchmark v5.0.0

Industry-standard security baseline:
- Identity and Access Management (Section 1)
- Storage (Section 2)
- Logging (Section 3)
- Monitoring (Section 4)
- Networking (Section 5)

### 3. AWS Resource Tagging Standard v1.0.0

Ensures proper resource tagging for:
- Cost allocation
- Access control
- Automation
- Compliance

## Slack Integration

### Lambda Function Behavior

The Lambda function (`security_alert_normalizer.py`) intelligently processes findings:

1. **Filtering**: Only `HIGH` and `CRITICAL` severity findings are forwarded
2. **Normalization**: Supports both classic ASFF and new OCSF/V2 finding formats
3. **Formatting**: Creates rich Slack messages with color-coding
4. **Metadata**: Includes account, region, resource, finding types, threats

### Severity Color Coding

| Severity | Color | Hex Code |
|----------|-------|----------|
| **CRITICAL** | Dark Red | `#8B0000` |
| **HIGH** | Red | `#FF0000` |
| **MEDIUM** | Orange | `#FFA500` (suppressed) |
| **LOW** | Yellow | `#FFFF00` (suppressed) |
| **INFORMATIONAL** | Blue | `#439FE0` (suppressed) |

### Example Slack Message

```
🔴 CRITICAL Security Finding

Title: [EC2.1] Amazon EBS snapshots should not be public
Severity: CRITICAL
Source: AWS Security Hub
Account: 123456789012
Region: eu-west-2
Resource: snap-0123456789abcdef

Description:
This control checks whether Amazon Elastic Block Store snapshots are 
not publicly restorable. EBS snapshots should not be publicly restorable 
by everyone unless you explicitly allow it, to avoid accidental exposure 
of data.

Types:
["Effects/Data Exposure", "Software and Configuration Checks"]

Open in AWS Console
```

## Email Handler Integration (Beautiful HTML Emails)

### Lambda Function Behavior

The email handler Lambda function (`security_alert_email_handler.py`) provides a much better email experience than basic SNS emails:

1. **Filtering**: Only `HIGH` and `CRITICAL` severity findings are sent
2. **Beautiful HTML**: Professional, color-coded emails with proper formatting
3. **Responsive Design**: Works on desktop and mobile devices
4. **Metadata Rich**: Includes all finding details, remediation steps, and direct links
5. **Dual Format**: HTML for modern clients + plain text fallback

### Email Features

| Feature | Basic SNS Email | Lambda HTML Email |
|---------|----------------|-------------------|
| **Formatting** | Plain text, JSON dump | Beautiful HTML with styling |
| **Severity Filtering** | All severities | Only HIGH/CRITICAL |
| **Color Coding** | No | Yes (red for CRITICAL, orange for HIGH) |
| **Remediation Steps** | No | Yes (highlighted green box) |
| **Responsive Design** | No | Yes (mobile-friendly) |
| **Direct Links** | No | Yes (button to AWS Console) |
| **Professional Look** | No | Yes (gradient headers, cards, grid layout) |

### Example HTML Email

The email includes:

**Header Section** (gradient background with severity color):
- 🔴/🟠 Emoji indicator
- Severity level in badge
- Finding title

**Finding Details Section** (grid layout):
- Source (AWS Security Hub, GuardDuty, etc.)
- AWS Account ID
- AWS Region
- Affected Resource
- Created timestamp

**Description Section** (yellow info box):
- Full finding description

**Remediation Section** (green action box):
- Step-by-step remediation instructions
- Recommended actions

**Additional Metadata** (code blocks):
- Finding types
- Threat indicators (if any)

**Action Button**:
- Direct link to AWS Security Hub console

### Setting Up Amazon SES

Before using the email handler, configure Amazon SES:

**1. Verify Sender Email**:
```bash
# Verify the FROM email address
aws ses verify-email-identity --email-address security-alerts@company.com
```

**2. Verify Recipient Emails (if in sandbox)**:
```bash
# In SES sandbox, verify each recipient
aws ses verify-email-identity --email-address security-team@company.com
aws ses verify-email-identity --email-address oncall@company.com
```

**3. Request Production Access** (recommended):
```
AWS Console → SES → Account dashboard → Request production access
```

Benefits of production access:
- Send to any email address (no verification needed)
- Higher sending limits
- Better deliverability

**4. (Optional) Configure Custom Domain**:
```bash
# Verify your domain
aws ses verify-domain-identity --domain company.com

# Add DNS records (DKIM, SPF, DMARC) for better deliverability
```

### Cost Comparison

| Method | Cost | Pros | Cons |
|--------|------|------|------|
| **SNS Email** | Free (first 1,000) | Simple, no setup | Ugly, all findings, no filtering |
| **Lambda + SES** | $0.10 per 1,000 emails | Beautiful, filtered, professional | Requires SES setup |

Typical monthly cost for Lambda + SES: **~$0.10** (assuming 100 HIGH/CRITICAL findings/month)

### Customizing Email Templates

To customize the HTML email template, edit `lambda/security_alert_email_handler.py`:

```python
# Change colors
SEVERITY_COLOR = {
    "CRITICAL": "#YOUR_COLOR",  # Default: #8B0000 (dark red)
    "HIGH": "#YOUR_COLOR",       # Default: #FF0000 (red)
}

# Modify HTML structure in the html_body variable
html_body = f"""
    <!-- Your custom HTML here -->
"""
```

After making changes:
1. Zip the updated Lambda function
2. Run `terraform apply` to update

## Slack Integration

### Typical Production Environment

| Component | Volume | Unit Cost | Monthly Cost |
|-----------|--------|-----------|--------------|
| **Security Hub - Findings** | 10,000 | Free (first 10k) | $0.00 |
| **Security Hub - Findings** | 50,000 (additional) | $0.0010/finding | $50.00 |
| **CloudWatch Alarms** | 8 alarms | $0.10/alarm | $0.80 |
| **Lambda Invocations** | 1,000 | Free (first 1M) | $0.00 |
| **Lambda Duration** | 100 GB-seconds | $0.0000166667/GB-sec | $0.02 |
| **SNS Email** | 1,000 | Free (first 1,000) | $0.00 |
| **EventBridge Events** | 10,000 | Free (first 1M) | $0.00 |
| **TOTAL** | | | **~$50.82/month** |

### Cost Optimization Tips

1. **Reduce Findings Volume**: Configure finding filters to suppress low-value findings
   ```terraform
   # In AWS Console: Security Hub → Settings → Findings → Suppression rules
   ```

2. **Disable Unused Standards**: Only enable standards you actively monitor
   ```terraform
   # Comment out unused standards in security_hub.tf
   ```

3. **Increase Alarm Period**: Longer evaluation periods reduce alarm charges
   ```terraform
   # Modify period in trail_security_alarms.tf
   period = 900  # 15 minutes instead of 300 (5 minutes)
   ```

4. **Use Consolidated Alarms**: Combine multiple metrics into composite alarms
   ```terraform
   resource "aws_cloudwatch_composite_alarm" "security_composite" {
     alarm_name = "all-security-alarms"
     alarm_rule = "ALARM(unauthorized_api_calls) OR ALARM(root_account_usage)"
   }
   ```

## Integration Examples

### With GuardDuty Module

```terraform
# Enable GuardDuty
module "guardduty" {
  source = "../../modules/security/guard_duty"

  env        = "production"
  project_id = "cerpac"

  enable_guardduty = true
}

# Security Hub automatically ingests GuardDuty findings
module "security_hub" {
  source = "../../modules/security/security_hub"

  env        = "production"
  project_id = "cerpac"

  enable_security_hub = true
  
  depends_on = [module.guardduty]
}
```

### With AWS Config Module

```terraform
# Enable AWS Config (REQUIRED for Security Hub standards)
module "aws_config" {
  source = "../../modules/security/aws_config"

  env        = "production"
  project_id = "cerpac"

  enable_aws_config = true
  
  # Enable all resource types for comprehensive coverage
  record_all_resources     = true
  include_global_resources = true
}

# Security Hub leverages Config rules for standards compliance
# IMPORTANT: Many Security Hub controls will not work without AWS Config
module "security_hub" {
  source = "../../modules/security/security_hub"

  env        = "production"
  project_id = "cerpac"

  enable_security_hub              = true
  enable_aws_foundational_standard = true  # Requires AWS Config
  enable_cis_standard              = true  # Requires AWS Config
  enable_resource_tagging_standard = true  # Requires AWS Config
  
  # AWS Config must be enabled first
  depends_on = [module.aws_config]
}
```

**Why AWS Config is Required**:
- AWS Foundational Security Best Practices: ~100 controls, many use Config Rules
- CIS AWS Foundations Benchmark: ~50 controls, majority use Config Rules
- Resource Tagging Standard: All controls use Config Rules
- Without Config, these controls will show as "NOT_AVAILABLE" in Security Hub

### With CloudTrail Module

```terraform
# Enable CloudTrail
module "cloudtrail" {
  source = "../../modules/security/cloud_trail"

  env            = "production"
  project_id     = "cerpac"
  retention_days = 90
}

# Security Hub alarms depend on CloudTrail logs
module "security_hub" {
  source = "../../modules/security/security_hub"

  env        = "production"
  project_id = "cerpac"

  enable_cloudtrail_security_alarms = true
  
  depends_on = [module.cloudtrail]
}
```

## Troubleshooting

### No Findings Appearing in Security Hub

**Issue**: Security Hub enabled but no findings visible

**Possible Causes**:
1. Standards still initializing (takes 1-2 hours)
2. AWS Config not enabled (many controls require Config Rules)
3. No resources violating controls
4. GuardDuty not enabled or no threats detected

**Fix**:
```bash
# Check Security Hub status
aws securityhub describe-hub

# List standards subscriptions
aws securityhub get-enabled-standards

# Check if AWS Config is enabled
aws configservice describe-configuration-recorders

# Check GuardDuty detector
aws guardduty list-detectors
```

### Security Hub Controls Showing "NOT_AVAILABLE"

**Issue**: Many controls show status "NOT_AVAILABLE" instead of PASSED/FAILED

**Cause**: AWS Config is not enabled or Config Recorder is stopped

**Impact**: 
- AWS Foundational Security Best Practices: ~70% of controls unavailable
- CIS AWS Foundations Benchmark: ~60% of controls unavailable
- Resource Tagging Standard: 100% of controls unavailable

**Fix**:
```bash
# Check if Config is enabled
aws configservice describe-configuration-recorders

# Check Config recorder status
aws configservice describe-configuration-recorder-status

# Enable Config if not already enabled (use Terraform module)
# Or manually start the recorder
aws configservice start-configuration-recorder \
  --configuration-recorder-name default
```

**Solution**: Enable AWS Config module before Security Hub:
```terraform
# Enable AWS Config FIRST
module "aws_config" {
  source = "../../modules/security/aws_config"
  
  env               = "production"
  project_id        = "cerpac"
  enable_aws_config = true
}

# Then enable Security Hub
module "security_hub" {
  source = "../../modules/security/security_hub"
  
  env                 = "production"
  project_id          = "cerpac"
  enable_security_hub = true
  
  depends_on = [module.aws_config]
}
```

### Alarms Not Triggering

**Issue**: CloudWatch alarms never enter ALARM state

**Possible Causes**:
1. CloudTrail not streaming to CloudWatch Logs
2. Log group name mismatch
3. No actual security events occurring

**Fix**:
```bash
# Verify log group exists
aws logs describe-log-groups \
  --log-group-name-prefix /aws/cloudtrail/

# Test with simulated root login (CAREFUL!)
aws sts get-caller-identity

# Check metric filter
aws logs describe-metric-filters \
  --log-group-name /aws/cloudtrail/production-audit-trail
```

### Lambda Not Forwarding to Slack

**Issue**: Slack messages not appearing

**Possible Causes**:
1. Incorrect webhook URL
2. Lambda execution errors
3. Findings below HIGH severity (suppressed)

**Fix**:
```bash
# Check Lambda logs
aws logs tail /aws/lambda/production-security-alert-normalizer --follow

# Test Lambda manually
aws lambda invoke \
  --function-name production-security-alert-normalizer \
  --payload file://test-event.json \
  response.json

# Check Lambda environment variables
aws lambda get-function-configuration \
  --function-name production-security-alert-normalizer
```

### High Security Hub Costs

**Issue**: Unexpectedly high Security Hub charges

**Causes**: Large number of findings ingested

**Solutions**:

1. **Enable Suppression Rules**:
   ```
   AWS Console → Security Hub → Settings → Findings → Suppression rules
   Suppress PASSED findings
   Suppress LOW severity findings
   ```

2. **Disable Unused Standards**:
   ```terraform
   # Comment out standards not actively monitored
   # resource "aws_securityhub_standards_subscription" "resource_tagging" {
   #   ...
   # }
   ```

3. **Use Finding Aggregation**:
   ```bash
   # Enable regional aggregation
   aws securityhub create-finding-aggregator \
     --region-linking-mode ALL_REGIONS
   ```

## Best Practices

### ✅ Recommended

- [x] Enable Security Hub in all regions
- [x] Subscribe to all three core standards
- [x] Enable GuardDuty for threat detection
- [x] Configure Slack integration for real-time alerts
- [x] Set up email alerts for compliance team
- [x] Review findings weekly in Security Hub console
- [x] Enable CloudTrail security alarms (CIS compliance)
- [x] Test alarm notification flow monthly
- [x] Document incident response procedures
- [x] Use tagging standard for resource governance

### ❌ Avoid

- [ ] Disabling Security Hub to save costs (security > cost)
- [ ] Ignoring MEDIUM severity findings
- [ ] Not responding to HIGH/CRITICAL findings within 24 hours
- [ ] Using only email alerts (easy to miss)
- [ ] Not testing Slack integration
- [ ] Disabling standards without review
- [ ] Suppressing all findings to reduce noise

## Compliance Mapping

| Standard | Coverage | Status |
|----------|----------|--------|
| **CIS AWS Foundations Benchmark** | 5 alarms + standard subscription | ✅ Full |
| **AWS Foundational Security** | Standard subscription (100+ controls) | ✅ Full |
| **PCI-DSS** | Logging, monitoring, access controls | ✅ Supported |
| **HIPAA** | Audit trails, encryption, access logs | ✅ Supported |
| **SOC 2** | Security monitoring, incident response | ✅ Supported |
| **GDPR** | Breach detection, audit logs | ✅ Supported |
| **ISO 27001** | Security monitoring and logging | ✅ Supported |
| **NIST 800-53** | Continuous monitoring (SI-4) | ✅ Supported |

## Variables Reference

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `env` | string | - | Yes | Environment name |
| `project_id` | string | - | Yes | Project identifier |
| `enable_security_hub` | bool | `true` | No | Enable Security Hub (master toggle) |
| `enable_aws_foundational_standard` | bool | `true` | No | Enable AWS Foundational Security Best Practices v1.0.0 |
| `enable_cis_standard` | bool | `true` | No | Enable CIS AWS Foundations Benchmark v5.0.0 |
| `enable_resource_tagging_standard` | bool | `false` | No | Enable AWS Resource Tagging Standard v1.0.0 |
| `enable_guardduty_integration` | bool | `true` | No | Enable GuardDuty product subscription |
| `enable_security_alerting` | bool | `true` | No | Enable EventBridge findings routing to SNS |
| `security_alerts_sns_topic_arn` | string | - | Yes* | SNS topic ARN from security_notification module (* required if alerting enabled) |

**Note**: Email, Slack, and SES configuration are now managed by the `security_notification` module, not this module. See the security_notification module README for alerting configuration options.

## Related Modules

- **security_notification**: SNS topic, email, and Slack alerting (required for notifications)
- **cloud_trail**: Audit logging with CIS compliance alarms
- **guard_duty**: Threat detection (integrated with Security Hub)
- **aws_config**: Configuration compliance (required for Security Hub standards)
- **waf**: Web application firewall (findings integrated with Security Hub)

## Support

For issues or questions:
- Internal: Contact Security Team
- Documentation: See [AWS Security Hub Documentation](https://docs.aws.amazon.com/securityhub/)
- Architecture: See [2DArchitecture.md](./2DArchitecture.md)

---

**Last Updated**: January 14, 2026  
**Version**: 2.0.0  
**Maintained By**: Security Team

