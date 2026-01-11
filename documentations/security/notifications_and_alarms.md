# Production Notifications and Alarms – How They Work (CERPAC)

This guide explains exactly how security notifications and alarms are generated in production, how to turn them on/off, what events trigger them, and where they are defined in Terraform.

---

## High-level Flow

- GuardDuty findings (High/Critical) → EventBridge → SNS → Email (+ optional Slack)
- Security Hub failed controls → EventBridge → SNS → Email (+ optional Slack)
- CloudTrail account-activity anomalies → CloudWatch Metric Filters/Alarms → SNS → Email (+ optional Slack)
- Infrastructure change awareness (SG/VPC/S3 policy) → CloudWatch Alarms → SNS → Email (+ optional Slack)

SNS can fan out to:
- Email (native SNS subscription)
- Slack (via SNS → Lambda → Slack Incoming Webhook)

---

## On/Off Switches (Toggles)

EventBridge + SNS Alerting
- Variable (module): enable_security_alerting (bool)
- Behavior in production: automatically enabled when either `security_alert_email` or `security_slack_webhook_url` is provided by the environment.
- Where set:
  - Module variables defined in: `production-infrastructure/cerpac_security_alerting.tf`
  - Environment wiring (auto-derives enable from provided values): `environments/production/main.tf`
  - Values provided in tfvars object: `environments/production/terraform.tfvars` → `security_alerting.email`, `security_alerting.slack_webhook_url`

CloudTrail Security Alarms (Account Activity – CIS controls)
- Variable (module): enable_cloudtrail_security_alarms (bool)
- File: `production-infrastructure/cerpac_cloudtrail_alarms.tf`
- Note: This is the single baseline for CIS 4.3/4.4/4.5 in production.

CloudTrail Infrastructure Change Alarms (Change Awareness)
- Variable (module): enable_cloudtrail_infra_alarms (bool)
- File: `production-infrastructure/cerpac_cloudtrail_infra_alarms.tf`
- These are complementary (no overlap with the baseline CIS controls).

---

## Triggers (What generates alerts)

EventBridge Rules → SNS
- GuardDuty High/Critical findings
  - Rule file: `production-infrastructure/cerpac_security_alerting.tf`
  - Pattern: source = aws.guardduty, detail-type = GuardDuty Finding, severity ≥ 7
  - Target formatting: InputTemplate → Valid JSON string (multiline with \n) → SNS
- Security Hub failed compliance controls
  - Rule file: `production-infrastructure/cerpac_security_alerting.tf`
  - Pattern: source = aws.securityhub, detail-type = Security Hub Findings - Imported, detail.findings[].Compliance.Status = FAILED
  - Target formatting: includes title, severity, account, region, resource

CloudWatch Metric Filters/Alarms (via CloudTrail → CloudWatch Logs)
- Baseline (enable_cloudtrail_security_alarms): `cerpac_cloudtrail_alarms.tf`
  - Unauthorized API calls (AccessDenied*/UnauthorizedOperation)
  - Root account usage
  - Console login without MFA
  - IAM policy changes
  - CloudTrail stopped / deleted / updated
- Infrastructure Changes (enable_cloudtrail_infra_alarms): `cerpac_cloudtrail_infra_alarms.tf`
  - Security group ingress/egress/create/delete
  - VPC route/gateway create/delete (VPC, routes, NAT/IGW)
  - S3 bucket policy put/delete

All alarms publish to: `${var.env}-cerpac-security-alerts` SNS topic

---

## Prerequisites (Wiring that must be in place)

CloudTrail
- Multi-region trail with S3 storage is configured in `cerpac_cloud_trail.tf`
- CloudTrail → CloudWatch Logs integration is enabled (wired) in the same file via:
  - cloud_watch_logs_group_arn = aws_cloudwatch_log_group.cloudtrail.arn
  - cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

SNS Topic and Subscriptions
- Topic: `${var.env}-cerpac-security-alerts` (in `cerpac_security_alerting.tf`)
- Email: native SNS email subscription (confirm via inbox)
- Slack: via Lambda forwarder (`cerpac_security_slack_lambda.tf`) if `security_slack_webhook_url` is provided

Security Services
- GuardDuty detector enabled (`cerparc_guard_duty.tf`) with S3 protection
- Security Hub account + standards enabled (`cerparc_security_hub.tf`) and GuardDuty product subscription

WAF Logging (context)
- WAF logs → Firehose → Lambda router → S3 dynamic partitions (allowed/, blocked/, errors/)
- Files: `cerpac_waf.tf`, `cerpac_waf_logging.tf`, `cerpac_waf_firehose.tf`, `cerpac_waf_lambda.tf`

---

## How to Enable / Disable

EventBridge + SNS Alerting (global on/off)
- How it enables: main.tf automatically sets `enable_security_alerting = true` when either of these is present in tfvars:
  - `security_alerting.email`
  - `security_alerting.slack_webhook_url`
- To enable: provide one or both values in `environments/production/terraform.tfvars`:
  security_alerting = {
    email            = "security-team@example.com"
    slack_webhook_url = "https://hooks.slack.com/services/XXX/YYY/ZZZ"
  }
- To disable: remove both values (or set both to null). No separate `enabled` flag is required.

CloudTrail Account-Activity Alarms (baseline CIS controls)
- Toggle: `enable_cloudtrail_security_alarms` (bool)
- Where set: `security_alerting.enable_cloudtrail_security_alarms` in tfvars
- File: `cerpac_cloudtrail_alarms.tf`

Infrastructure Change Alarms
- Toggle: `enable_cloudtrail_infra_alarms` (bool)
- Where set: `security_alerting.enable_cloudtrail_infra_alarms` in tfvars
- File: `cerpac_cloudtrail_infra_alarms.tf`

---

## Where alerts go

- Email: to `security_alert_email`
- Slack: to `security_slack_webhook_url` via Lambda forwarder
- Optionally: add more subscriptions to the SNS topic (PagerDuty, HTTPS endpoints, etc.)

---

## Noise Reduction / Tuning Tips

- GuardDuty severity threshold: keep at ≥ 7 for production (reduce noise)
- ConsoleLogin without MFA: scope to successful logins only if needed
  - Pattern add: `$.responseElements.ConsoleLogin = "Success"`
- Unauthorized API calls: exclude known benign sources (SCP/Control Tower)
  - E.g., exclude specific userAgent or service principals
- TreatMissingData: For quiet accounts, consider setting alarm treat_missing_data to not_breaching

---

## Testing

Email path
- Confirm the SNS email subscription from your inbox
- Force a Security Hub FAILED control (lab/test) and verify alert arrives

Slack path
- Ensure `security_slack_webhook_url` is set and the Lambda is deployed
- Publish a test SNS message to the topic to verify the webhook delivery

Metric filters
- In a sandbox, perform a benign AccessDenied API call (e.g., a read without permission) and ensure the Unauthorized API Calls alarm fires
- For MFA test: attempt a console login without MFA in a test account (if policy allows)

---

## File Map (Production)

- EventBridge + SNS alerting: `production-infrastructure/cerpac_security_alerting.tf`
- Slack forwarder Lambda: `production-infrastructure/cerpac_security_slack_lambda.tf`
- CloudTrail (S3 + CloudWatch Logs): `production-infrastructure/cerpac_cloud_trail.tf`
- CloudTrail security alarms (baseline): `production-infrastructure/cerpac_cloudtrail_alarms.tf`
- CloudTrail infra-change alarms: `production-infrastructure/cerpac_cloudtrail_infra_alarms.tf`
- GuardDuty: `production-infrastructure/cerparc_guard_duty.tf`
- Security Hub (standards + integration): `production-infrastructure/cerparc_security_hub.tf`
- WAF + logging: `production-infrastructure/cerpac_waf.tf`, `cerpac_waf_logging.tf`, `cerpac_waf_firehose.tf`, `cerpac_waf_lambda.tf`

---

## Notes & Gotchas

- Alerting enablement is now derived from presence of `email` or `slack_webhook_url` in `security_alerting`. If both are absent, alerting is OFF.
- Email subscriptions require manual confirmation before alerts are delivered.
- Keep secrets (AWS keys, DB passwords, webhooks) out of version control—use Terraform Cloud workspace variables.
