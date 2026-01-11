# CloudTrail Module – Architecture & Operations

This module sets up production-grade audit logging and security alerting by stitching together:

- CloudTrail (multi-region audit trail)
- S3 (central log storage)
- CloudWatch Logs (streaming + metric filters)
- EventBridge (findings routing)
- SNS + Lambda (notifications & Slack normalization)
- Security Hub (posture, standards)
- GuardDuty (threat detection)
- AWS Config (continuous configuration recording)

## 2D Architecture Diagram

```
                                           +-------------------------+
                                           |     S3 (Config Logs)    |
                                           |  (AWS Config snapshots) |
                                           +-------------------------+
                                                      ^
                                                      |
                                                      | S3 delivery (retention)
+-------------+   records   +----------------------+  |
| AWS Config  | ----------> | Live Config State    |  |
| (recorder)  |             | (service-managed)    |  |
+-------------+             +----------------------+  |
         |                              |              |
         | evaluates against            |              |
         v                              v              |
+-----------------+          Config Rule evaluations   |
|  Config Rules   | -----------------------------------+
| (managed/custom)|
+-----------------+
         |
         | Config Rules findings
         v
+-------------------------------+
|        AWS Security Hub       |
|  (Standards + Findings Bus)   |
+-------------------------------+
   ^                     ^
   |                     |
   | GuardDuty findings  | Findings from other services
   |                     | (Inspector, IAM Access Analyzer, etc.)
   |                     |
   |                     |
   |                                      CloudWatch alarms/metrics
   |                                             |
   |                                             v
   |                                 +------------------------+
   |                                 | Metric Filters/Alarms |
   |                                 |    (CIS & Infra)      |
   |                                 +------------------------+
   |                                             ^
   |                                             |
   |                                    +------------------+
   | logs (/aws/cloudtrail)             | CloudWatch Logs  |
   |                                    | (/aws/cloudtrail)|
   |                                    +------------------+
   |                                             ^
   |                                             |
   |        logs                                 |
   |  +----------------+                         |
   |  |                |                         |
   |  |  CloudTrail    |                         |
   |  | (Multi-region) |                         |
   |  +----------------+                         |
   |      |      |                               |
   |      |      | generates events              |
   |      |      +-------------------------------+
   |      |                                      |
   |      | S3 writes                            |
   |      v                                      v
   |  +---------------------+        +------------------------+
   |  | S3 Bucket (Logs)    |        |      EventBridge       |
   |  |  (CloudTrail logs)  |        | (Rules for SecurityHub |
   |  +---------------------+        |  findings & alarms)    |
   |                                  +------------------------+
   |                                            |
   |                                            | routes notifications
   |                                            v
   |                                 +------------------------+
   |                                 |          SNS           |
   |                                 |      Alerts Topic      |
   |                                 +------------------------+
   |                                      |           |
   |                                      |           | Lambda subscriptions
   |                                      v           v
   |                          +-------------------+  +--------------------+
   |                          | Lambda Email      |  | Lambda Slack       |
   |                          | Handler           |  | Handler            |
   |                          | (HIGH/CRITICAL)   |  | (HIGH/CRITICAL)    |
   |                          | - Beautiful HTML  |  | - Rich text blocks |
   |                          | - Send via SES    |  | - Slack webhook    |
   |                          +-------------------+  +--------------------+
   |                                   |                      |
   |                                   v                      v
   |                          +----------------+    +------------------+
   |                          |  Email Inbox   |    |  Slack Channel   |
   |                          | (HTML emails)  |    | #security-alerts |
   |                          +----------------+    +------------------+
   |
   | CloudTrail events (for GuardDuty)
   v
+-------------------+       +-------------------+       +-------------------+
| CloudTrail Events | ----> |                   | <---- |   VPC Flow Logs   |
| (from above)      |       |     GuardDuty     |       | (network traffic) |
+-------------------+       |     Detector      |       +-------------------+
                            | (Threat Intel &   |
+-------------------+       |  Anomaly Engine)  |
|     DNS Logs      | ----> |                   |
| (query patterns)  |       +-------------------+
+-------------------+              |
                                   | (optional) S3 data events / EKS audit logs
                                   v
                          +-------------------------+
                          |   S3 Malware Scan       |
                          |   (if enabled)         |
                          +-------------------------+
                                   |
                                   v
                          +-------------------------+
                          |   GuardDuty Findings    |
                          +-------------------------+
                                   |
                                   | publishes findings
                                   v
                          +-------------------------------+
                          |        AWS Security Hub       |
                          | (ingests GuardDuty findings   |
                          |  from the left side here)     |
                          +-------------------------------+

```


### AWS Config – Integration Notes
- AWS Config operates independently to record resource configurations and changes over time.
- It does not directly affect CloudTrail, CloudWatch metric filters/alarms, EventBridge routing, or SNS/Lambda notifications by itself.
- To drive alerts from AWS Config, you need Config Rules (managed or custom). Their evaluations can:
  - Surface in Security Hub as control findings (many Security Hub standards leverage Config-managed rules), and
  - Be routed via EventBridge if you add specific rules/targets for Config rule state changes.
- In this module, AWS Config is enabled for recording and log delivery to S3. Alerting is primarily driven by:
  - CloudTrail + CloudWatch metric filters (CIS/infrastructure changes), and
  - Security Hub + EventBridge (findings to SNS/Lambda).

## How Components Work Together

- CloudTrail
  - Captures management and data events across regions.
  - Streams to CloudWatch Logs for real-time metrics/alarms and delivers to S3 for immutable retention.
  - IAM role allows CloudTrail to write to CloudWatch Logs.

- CloudWatch Logs
  - Log group: `/aws/cloudtrail/<env>-<project_id>-audit-trail`.
  - Metric filters implement CIS/AWS Foundational detections (root logins, unauthorized API calls, CloudTrail disabled, IAM policy changes, infra changes like SG/VPC routes).
  - Alarms publish to the central SNS topic.

- EventBridge
  - Rules listen for Security Hub imported findings (classic + V2) and route raw events to SNS and/or Lambda.
  - Can be extended with catch-all diagnostics when debugging, behind a toggle.

- SNS + Lambda Handlers
  - SNS topic centralizes alert delivery from CloudWatch alarms and EventBridge.
  - **Lambda Email Handler** (security_alert_email_handler.py):
    - Formats Security Hub/GuardDuty findings into beautiful HTML emails.
    - Sends via Amazon SES to specified email addresses.
    - Only HIGH/CRITICAL severities are forwarded; others are suppressed.
    - Includes remediation steps, color-coded severity, and responsive design.
    - Logs decisions and delivery outcomes to CloudWatch Logs.
  - **Lambda Slack Handler** (security_alert_normalizer.py):
    - Formats Security Hub/GuardDuty findings into Slack messages.
    - Only HIGH/CRITICAL severities are forwarded; others are suppressed (configurable).
    - Sends via Slack webhook to specified channel.
    - Logs decisions and delivery outcomes to CloudWatch Logs.
  - Both Lambda functions subscribe to the same SNS topic for parallel processing.

- Security Hub
  - Enabled per account/region and subscribed to core standards:
    - AWS Foundational Security Best Practices v1.0.0
    - CIS AWS Foundations Benchmark v5.0.0
    - AWS Resource Tagging Standard v1.0.0
  - Integrates GuardDuty findings via product subscription.

- GuardDuty
  - Continuously monitors AWS account activity and network traffic for threats (unauthorized behavior, malware, reconnaissance, credential compromise).
  - Analyzes CloudTrail events, VPC Flow Logs, and DNS logs to detect suspicious activity.
  - Detector enabled with optional features toggled (S3 data events/malware protection, EKS audit logs monitoring).
  - Generates its own findings independently based on threat intelligence and anomaly detection.
  - Findings are published to Security Hub via product subscription (shown in diagram as separate input).
  - Once in Security Hub, findings are routed to EventBridge → SNS/Lambda for alerting.

- AWS Config (Function in the scope)
  - Continuously records resource configuration changes across the account.
  - Stores configuration history in a dedicated S3 bucket (`<env>-<project_id>-aws-config-logs`).
  - Complements CloudTrail by providing "what the configuration is" over time, while CloudTrail records "who changed what".
  - Improves compliance posture by enabling auditors and automation to verify drift from baselines.

## Inputs (Key Variables)

- env: Environment name (production, staging)
- project_id: Short project identifier used in naming
- retention_days: Retention for CloudTrail logs and CloudWatch log group
- bucket_name_override: Optional custom name for the CloudTrail S3 bucket
- Toggles:
  - enable_cloudtrail_security_alarms
  - enable_cloudtrail_infra_alarms
  - enable_security_alerting
  - enable_security_hub
  - enable_guardduty (+ feature flags)
  - enable_aws_config

## Outputs (Grouped)

- cloudtrail (object):
  - bucket_name, bucket_arn
  - log_group_name, log_group_arn
  - trail_arn

## On/Off Switches

- Each feature has a var.enable_* toggle to control deployment:
  - CloudTrail security alarms
  - CloudTrail infra change alarms
  - Security alerting (EventBridge + SNS + Lambda)
  - Security Hub standards
  - GuardDuty detector and features
  - AWS Config recorder

## Troubleshooting Tips

- CloudTrail → CloudWatch ARN must include `:*` suffix for validation.
- Ensure SNS topic policy allows EventBridge `events.amazonaws.com` publish with SourceArn set to the rule.
- For Lambda alerting:
  - Set `LOG_LEVEL=DEBUG` for verbose CloudWatch logging.
  - Verify `SLACK_WEBHOOK_URL` is set.
  - Suppression currently ignores non-HIGH/CRITICAL severities.

## File Map (Module)

- `main.tf`: Core CloudTrail, S3, CloudWatch, IAM
- `trail_security_alarms.tf`: CIS security alarms (root usage, unauthorized API)
- `trail_infra_change_alarms.tf`: Infra alarms (SG/VPC/route/S3 policy changes)
- `security_hub.tf`: Security Hub enablement and standards
- `security_hub_alerting.tf`: EventBridge + SNS routing for findings
- `security_hub_alerting_slack_normalizer_lambda.tf`: Lambda forwarder setup
- `guard_duty.tf`: GuardDuty detector and features
- `aws_config.tf`: AWS Config recorder + S3 bucket for config logs
- `variables.tf`: Inputs and toggles
- `outputs.tf`: Grouped outputs
- `lambda/security_alert_normalizer.py`: Lambda source logic (suppression + Slack)

## Example Usage

Reference from a higher-level stack:

```hcl
module "cloudtrail" {
  source = "./modules/cloudtrail"

  env            = var.env
  project_id     = var.project_id
  retention_days = var.cloudtrail_retention_days

  bucket_name_override = var.cloudtrail_bucket_override # optional

  enable_cloudtrail_security_alarms = var.enable_cloudtrail_security_alarms
  enable_cloudtrail_infra_alarms    = var.enable_cloudtrail_infra_alarms
  enable_security_alerting          = var.enable_security_alerting
  enable_security_hub               = var.enable_security_hub
  enable_guardduty                  = var.enable_guardduty
  enable_aws_config                 = var.enable_aws_config

  security_alert_email        = var.security_alert_email
  security_slack_webhook_url  = var.security_slack_webhook_url
}

output "cloudtrail" {
  value = module.cloudtrail.cloudtrail
}
```
