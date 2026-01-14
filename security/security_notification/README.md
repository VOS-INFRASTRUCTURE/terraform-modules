# Security Notification Module

Terraform module for centralized security alerting via SNS, with optional email (basic SNS or SES-based) and Slack notifications.

## Overview

This module creates a central SNS topic for security alerts and provides flexible notification options:
- **Email Alerts**: Basic SNS email subscription or beautiful HTML emails via SES
- **Slack Alerts**: Lambda-based integration for HIGH/CRITICAL severity findings
- **Extensible**: Easy to add more notification channels

## Module Structure

```
security_notification/
├── main.tf                                          # SNS topic and basic email subscription
├── security_hub_alerting_email_handler_lambda.tf   # SES-based email handler (optional)
├── security_hub_alerting_slack_normalizer_lambda.tf # Slack integration (optional)
├── lambda/                                          # Lambda function code (zipped)
│   ├── security_alert_normalizer.zip               # Slack forwarder
│   └── security_alert_email_handler.zip            # Email formatter
├── variables.tf                                     # Input variables
├── outputs.tf                                       # Module outputs
└── README.md                                        # This file
```

## Features

✅ **Central SNS Topic**: Single source of truth for all security alerts  
✅ **Email Notifications**: Two options - basic SNS or beautiful SES emails  
✅ **Slack Integration**: Real-time alerts to Slack channels (HIGH/CRITICAL only)  
✅ **Lambda-based Filtering**: Smart filtering and formatting of alerts  
✅ **Severity-based Routing**: Only critical alerts to Slack, all to email  
✅ **Project Context**: Alerts include project name and environment  

## Prerequisites

### For Basic Email (SNS)
- Email address to receive alerts

### For SES-based Email Handler
- Amazon SES verified email addresses (both sender and recipients)
- Lambda function deployment package (`security_alert_email_handler.zip`)

### For Slack Integration
- Slack Incoming Webhook URL
- Lambda function deployment package (`security_alert_normalizer.zip`)

## Usage

### Minimal Configuration (SNS Topic Only)

```terraform
module "security_alerts" {
  source = "../../modules/security/security_notification"

  env        = "production"
  project_id = "my-project"
}
```

**Result**: Creates SNS topic only, no email or Slack alerts.

### Basic Email Alerts (Simple SNS Email)

```terraform
module "security_alerts" {
  source = "../../modules/security/security_notification"

  env        = "production"
  project_id = "my-project"

  # Enable basic SNS email subscription
  enable_email_alerts   = true
  security_alert_email  = "security@example.com"
}
```

**Result**: 
- Creates SNS topic
- Adds email subscription (requires manual confirmation)
- All alerts sent as plain text emails

### Beautiful HTML Email Alerts (SES-based)

```terraform
module "security_alerts" {
  source = "../../modules/security/security_notification"

  env        = "production"
  project_id = "my-project"

  # Enable SES-based email handler
  enable_email_alerts = true
  enable_email_handler = true
  
  ses_from_email = "noreply@example.com"  # Must be verified in SES
  ses_to_emails  = [
    "security-team@example.com",
    "devops@example.com"
  ]
}
```

**Result**:
- Creates SNS topic
- Deploys Lambda to format and send beautiful HTML emails
- Includes severity badges, finding details, and remediation links

### Slack Alerts Only

```terraform
module "security_alerts" {
  source = "../../modules/security/security_notification"

  env        = "production"
  project_id = "my-project"

  # Enable Slack notifications
  enable_slack_alerts        = true
  security_slack_webhook_url = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
}
```

**Result**:
- Creates SNS topic
- Deploys Lambda to forward HIGH/CRITICAL findings to Slack
- Rich formatting with severity colors and actionable buttons

### Full Configuration (Email + Slack)

```terraform
module "security_alerts" {
  source = "../../modules/security/security_notification"

  env        = "production"
  project_id = "my-project"

  # Email via SES
  enable_email_alerts  = true
  enable_email_handler = true
  ses_from_email       = "security@example.com"
  ses_to_emails        = ["security-team@example.com"]

  # Slack alerts
  enable_slack_alerts        = true
  security_slack_webhook_url = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

  # Optional: Custom log level
  lambda_log_level = "INFO"
}
```

**Result**:
- Email handler: All findings → beautiful HTML emails
- Slack handler: HIGH/CRITICAL only → Slack channel
- Complete visibility across multiple channels

## Variables Reference

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `env` | string | Environment (production, staging, development) |
| `project_id` | string | Project identifier (1-50 characters) |

### Email Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_email_alerts` | bool | `false` | Enable email notifications |
| `security_alert_email` | string | `null` | Email for basic SNS subscription |
| `enable_email_handler` | bool | `false` | Use SES-based Lambda email handler |
| `ses_from_email` | string | `null` | SES verified sender email |
| `ses_to_emails` | list(string) | `[]` | List of recipient emails |

### Slack Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_slack_alerts` | bool | `false` | Enable Slack notifications |
| `security_slack_webhook_url` | string | `null` | Slack incoming webhook URL (sensitive) |

### Advanced Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `lambda_log_level` | string | `INFO` | Lambda log level (DEBUG, INFO, WARNING, ERROR) |

## Outputs

This module provides a comprehensive `security_notification` output object:

```terraform
output "security_notification" {
  value = {
    # SNS Topic
    sns_topic = {
      arn          = "arn:aws:sns:..."
      id           = "..."
      name         = "production-my-project-security-alerts"
      display_name = "MY-PROJECT PRODUCTION Security Alerts"
    }

    # Email Configuration
    email = {
      enabled              = true
      basic_sns_enabled    = false
      ses_handler_enabled  = true
      ses_from_email       = "security@example.com"
      ses_to_emails        = ["security-team@example.com"]
      lambda_function_arn  = "arn:aws:lambda:..."
      lambda_function_name = "production-my-project-security-email-handler"
    }

    # Slack Configuration
    slack = {
      enabled              = true
      webhook_configured   = true
      lambda_function_arn  = "arn:aws:lambda:..."
      lambda_function_name = "production-my-project-security-alert-normalizer"
    }

    # Summary
    summary = {
      environment         = "production"
      project_id          = "my-project"
      email_enabled       = true
      slack_enabled       = true
      total_subscriptions = 2
    }
  }
}
```

### Using Outputs

```terraform
# Reference SNS topic in Security Hub
resource "aws_securityhub_finding" "example" {
  # ...
  action {
    action_type = "AWS_API_CALL"
    aws_api_call_action {
      api     = "PublishToTopic"
      service = "SNS"
    }
  }
  
  resources {
    id = module.security_alerts.security_notification.sns_topic.arn
  }
}

# Use in EventBridge rule
resource "aws_cloudwatch_event_target" "security_alerts" {
  rule      = aws_cloudwatch_event_rule.guardduty.name
  target_id = "SendToSNS"
  arn       = module.security_alerts.sns_topic_arn
}
```

## Email Options Comparison

| Feature | Basic SNS Email | SES Email Handler |
|---------|----------------|-------------------|
| **Setup Complexity** | Simple | Requires SES setup |
| **Email Format** | Plain text | Beautiful HTML |
| **Customization** | None | Fully customizable |
| **Filtering** | No | Yes (severity-based) |
| **Cost** | Free (SNS only) | Lambda + SES costs |
| **Confirmation Required** | Yes | No |
| **Use Case** | Quick setup, testing | Production, better UX |

## Notification Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    Security Services                            │
│  (Security Hub, GuardDuty, Config, CloudTrail, etc.)           │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     │ Findings/Events
                     ▼
            ┌────────────────────┐
            │    SNS Topic       │
            │ security-alerts    │
            └────────┬───────────┘
                     │
         ┌───────────┼───────────┐
         │           │           │
         ▼           ▼           ▼
┌────────────┐ ┌──────────┐ ┌──────────────┐
│   Email    │ │  Lambda  │ │   Lambda     │
│ (Basic SNS)│ │  Email   │ │    Slack     │
│            │ │ Handler  │ │  Normalizer  │
└────────────┘ └────┬─────┘ └──────┬───────┘
                    │                │
                    │ SES            │ HTTPS
                    ▼                ▼
              ┌──────────┐    ┌────────────┐
              │  Email   │    │   Slack    │
              │Recipients│    │  Channel   │
              └──────────┘    └────────────┘
```

## Lambda Functions

### Email Handler Lambda

**Purpose**: Format security findings into beautiful HTML emails and send via SES.

**Triggers**: All findings from SNS topic  
**Filtering**: Can filter by severity in code  
**Output**: HTML email with:
- Severity badge (color-coded)
- Finding details
- Affected resources
- Remediation recommendations
- Direct links to AWS Console

**Configuration**:
```python
Environment Variables:
- FROM_EMAIL: Sender email address
- TO_EMAILS: Comma-separated recipient list
- PROJECT_NAME: Project identifier for email subject
- LOG_LEVEL: Logging verbosity
```

### Slack Normalizer Lambda

**Purpose**: Normalize findings and forward HIGH/CRITICAL to Slack.

**Triggers**: All findings from SNS topic  
**Filtering**: Only HIGH (7-8.9) and CRITICAL (9-10) severity  
**Output**: Slack message with:
- Color-coded severity
- Finding title and description
- Affected resources
- Timestamp and environment
- Action buttons (if configured)

**Configuration**:
```python
Environment Variables:
- SLACK_WEBHOOK_URL: Slack incoming webhook
- PROJECT_NAME: Project identifier
- ENVIRONMENT: Environment name
- LOG_LEVEL: Logging verbosity
```

## Security Considerations

### Sensitive Variables

⚠️ **IMPORTANT**: The following variables contain sensitive information:

- `security_slack_webhook_url`: Mark as sensitive in Terraform
- `ses_from_email`: Consider using AWS Secrets Manager
- `ses_to_emails`: Review recipient list carefully

### IAM Permissions

The module creates minimal IAM permissions:

**Email Handler Lambda**:
- `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` (CloudWatch Logs)
- `ses:SendEmail`, `ses:SendRawEmail` (SES, scoped to FROM_EMAIL)

**Slack Handler Lambda**:
- `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` (CloudWatch Logs)

### Best Practices

1. **Use SES Email Handler** for production (better formatting, no manual confirmation)
2. **Verify SES emails** before deploying (sender and recipients)
3. **Test Slack webhook** before enabling in production
4. **Monitor Lambda logs** for delivery failures
5. **Set up SNS topic encryption** (add KMS key if needed)
6. **Review alert volume** to avoid notification fatigue

## Cost Estimate

### Monthly Costs (Typical Production)

| Component | Volume | Unit Cost | Monthly Cost |
|-----------|--------|-----------|--------------|
| **SNS Topic** | 1,000 notifications | $0.50/million | $0.00 |
| **SNS Email** | 1,000 notifications | $2.00/100,000 | $0.02 |
| **Lambda (Email)** | 1,000 invocations × 256MB × 1s | $0.0000166667/GB-sec | $0.43 |
| **Lambda (Slack)** | 100 invocations × 256MB × 1s | $0.0000166667/GB-sec | $0.04 |
| **SES** | 1,000 emails | $0.10/1,000 | $0.10 |
| **CloudWatch Logs** | 1 GB | $0.50/GB | $0.50 |
| **TOTAL** | | | **~$1.09/month** |

**Note**: Costs scale with alert volume. High-volume environments may incur higher Lambda and SES costs.

## Troubleshooting

### Email Not Received (Basic SNS)

1. Check spam/junk folder
2. Verify email address is correct
3. Check SNS subscription confirmation (email sent after creation)
4. Confirm subscription via link in email

### Email Not Received (SES Handler)

1. Check CloudWatch Logs for Lambda errors
2. Verify SES sender email is verified
3. Check SES sending limits and quotas
4. Verify recipient emails are not bouncing
5. Check SES reputation and sending status

### Slack Alerts Not Appearing

1. Verify webhook URL is correct
2. Check CloudWatch Logs for Lambda errors
3. Test webhook URL manually: `curl -X POST -H 'Content-type: application/json' --data '{"text":"Test"}' YOUR_WEBHOOK_URL`
4. Verify Lambda has internet access (if in VPC)
5. Check finding severity (only HIGH/CRITICAL forwarded)

### Lambda Function Errors

1. Check CloudWatch Logs: `/aws/lambda/<function-name>`
2. Verify environment variables are set correctly
3. Check Lambda execution role permissions
4. Verify Lambda function code is properly deployed (zip file)

## Examples

### Integration with Security Hub

```terraform
module "security_alerts" {
  source = "../../modules/security/security_notification"

  env        = "production"
  project_id = "my-project"

  enable_email_alerts  = true
  enable_email_handler = true
  ses_from_email       = "security@example.com"
  ses_to_emails        = ["security-team@example.com"]

  enable_slack_alerts        = true
  security_slack_webhook_url = var.slack_webhook_url  # From secrets
}

# Security Hub sends findings to SNS
resource "aws_securityhub_product_subscription" "guardduty" {
  product_arn = "arn:aws:securityhub:${data.aws_region.current.name}::product/aws/guardduty"
}

resource "aws_cloudwatch_event_rule" "security_hub_findings" {
  name        = "security-hub-findings"
  description = "Capture Security Hub findings"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
  })
}

resource "aws_cloudwatch_event_target" "sns" {
  rule      = aws_cloudwatch_event_rule.security_hub_findings.name
  target_id = "SendToSNS"
  arn       = module.security_alerts.sns_topic_arn
}

resource "aws_sns_topic_policy" "security_alerts" {
  arn = module.security_alerts.sns_topic_arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action = "SNS:Publish"
      Resource = module.security_alerts.sns_topic_arn
    }]
  })
}
```

### Integration with GuardDuty

```terraform
# Use same security_alerts module from above

resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "guardduty-findings"
  description = "Capture GuardDuty findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
  })
}

resource "aws_cloudwatch_event_target" "guardduty_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "SendToSNS"
  arn       = module.security_alerts.sns_topic_arn
}
```

## Related Modules

- **security_hub**: AWS Security Hub configuration
- **guard_duty**: GuardDuty threat detection
- **cloud_trail**: CloudTrail audit logging
- **aws_config**: AWS Config compliance monitoring

## Contributing

To update Lambda functions:

1. Modify Python code in `lambda/` directory
2. Zip the function: `cd lambda && zip security_alert_normalizer.zip security_alert_normalizer.py`
3. Update `source_code_hash` will trigger redeployment

## License

This module is part of the infrastructure-as-code repository.

## Support

For issues or questions:
1. Check CloudWatch Logs for Lambda functions
2. Review this README for common troubleshooting steps
3. Contact DevOps team

