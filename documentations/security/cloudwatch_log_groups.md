# CloudWatch Log Groups (Production) – Inventory and Usage

This document explains the CloudWatch Log Groups used in CERPAC production, what writes to them, how we use them (alerts, troubleshooting, forensics), and how to tune retention and costs.

---

## Summary (what we have)

1) /aws/cloudtrail/production-cerpac-audit-trail
- Source: AWS CloudTrail (multi‑region management events)
- Managed by: Terraform in `production-infrastructure/cerpac_cloud_trail.tf`
- Retention: 90 days (3 months)
- Used for:
  - CloudWatch Metric Filters + Alarms (CIS controls) in:
    - `cerpac_cloudtrail_alarms.tf` (account activity)
    - `cerpac_cloudtrail_infra_alarms.tf` (infra changes)
  - EventBridge/SNS alerting relies on these alarms
- Contains:
  - Account activity (who did what, when, where)
  - Sensitive metadata about API calls
- Notes:
  - Required for compliance and investigations
  - Wired to CW Logs via `cloud_watch_logs_group_arn` + `cloud_watch_logs_role_arn`

2) /aws/guardduty/malware-scan-events
- Source: GuardDuty Malware Protection
- Managed by: AWS (service-created log group)
- Retention: 90 days (3 months)
- Used for:
  - Forensics/triage of malware scan results
  - Complementary to GuardDuty findings (the findings drive alerts via EventBridge)
- Contains:
  - Malware scan event details
- Notes:
  - Not currently feeding alarms; we alert on GuardDuty findings directly

3) /aws/lambda/production-cerpac-sns-to-slack
- Source: Lambda function “production-cerpac-sns-to-slack”
- Managed by: Lambda (log group auto-created on first invoke)
- Retention: Never expire (default)
- Used for:
  - Troubleshooting SNS → Slack alert delivery
  - Observability for the Slack forwarder function
- Contains:
  - Alert payload summaries and delivery results
- Recommendation:
  - Set retention to 30–90 days to avoid unbounded growth
  - How: manage with Terraform `aws_cloudwatch_log_group` resource

4) /aws/lambda/production-cerpac-waf-log-router
- Source: Lambda function “production-cerpac-waf-log-router”
- Managed by: Lambda (log group auto-created on first invoke)
- Retention: Never expire (default)
- Used for:
  - Debugging WAF log routing (Firehose → Lambda → S3 dynamic partitions)
- Contains:
  - Processing results and partition key metadata for allowed/blocked/error events
- Recommendation:
  - Set retention to 14–30 days (short-lived troubleshooting logs)

---

## Log group ↔ S3 bucket mapping

| S3 Bucket | Purpose | Related Log Group(s) | Where defined |
|---|---|---|---|
| `production-cerpac-cloudtrail-logs` | CloudTrail audit logs (S3) | `/aws/cloudtrail/production-cerpac-audit-trail` (CloudTrail → CloudWatch Logs) | `cerpac_cloud_trail.tf` (S3: `aws_s3_bucket.cloudtrail_logs`, Log Group: `aws_cloudwatch_log_group.cloudtrail`, CloudTrail: `aws_cloudtrail.cerpac_audit`)
| `production-cerpac-app-alb-waf-logs` | WAF request logs (partitioned: allowed/blocked/errors) | `/aws/lambda/production-cerpac-waf-log-router` (processor logs) | `cerpac_waf_logging.tf` (S3), `cerpac_waf_firehose.tf` (Firehose), `cerpac_waf_lambda.tf` (Lambda) — Firehose CloudWatch logging not configured
| `production-cerpac-aws-config-logs` | AWS Config snapshots and configuration history | (no CloudWatch Log Group; AWS Config delivers directly to S3) | `cerpac_aws_config.tf` (S3 + delivery channel)
| `production-cerpac-cloud-storage-03-api` | Application data (S3) | (no CloudWatch Log Group mapping) | `s3-cloud-storage-03-api.tf`
| `production-cerpac-cloud-storage-04-insurance` | Application data (S3) | (no CloudWatch Log Group mapping) | `s3-cloud-storage-04-insurance.tf`
| `production-cerpac-cloud-storage-mysql-db-backup-01` | MySQL backups (S3) | (no CloudWatch Log Group mapping) | `s3-cloud-storage-mysql-db -backup-01.tf`
| `production-cerpac-cloud-storage-postgres-db-backup-01` | PostgreSQL backups (S3) | (no CloudWatch Log Group mapping) | `s3-cloud-storage-postgres-db -backup-01.tf`

Notes:
- CloudTrail: we capture management events to S3 and mirror them to CloudWatch Logs for real‑time alarms. Both stores are active.
- WAF: traffic logs go to S3 via Firehose; Firehose and the processing Lambda each write their own CloudWatch logs for troubleshooting.
- AWS Config: writes snapshots/history directly to its S3 bucket; no CloudWatch Log Group is used by default.
- Application/backup buckets: not tied to CloudWatch Log Groups; they are regular storage.

---

## Do these log groups also write to S3?

Note: CloudWatch Log Groups themselves do not “write to S3.” Some AWS services deliver events to both S3 and CloudWatch Logs. The table below clarifies which log sources have an S3 destination configured in production.

| CloudWatch Log Group | Direct S3 Delivery? | S3 Bucket (if any) | Notes |
|---|---|---|---|
| `/aws/cloudtrail/production-cerpac-audit-trail` | Yes (via CloudTrail service) | `production-cerpac-cloudtrail-logs` | CloudTrail delivers management events to S3 and mirrors them to this log group for real-time alarms. |
| `/aws/guardduty/malware-scan-events` | No | — | GuardDuty findings are alerted via EventBridge; malware scan events are retained in CloudWatch Logs only. |
| `/aws/lambda/production-cerpac-sns-to-slack` | No | — | Lambda function logs remain in CloudWatch Logs unless exports are configured (not enabled). |
| `/aws/lambda/production-cerpac-waf-log-router` | No | — | Lambda function logs remain in CloudWatch Logs; WAF request data itself goes to S3 via Firehose. |

Related non–CloudWatch sources that deliver to S3 directly:
- AWS Config → `production-cerpac-aws-config-logs` (no CloudWatch Log Group)
- WAF request logs → `production-cerpac-app-alb-waf-logs` (via Firehose)

---

## How these log groups power alerts

- CloudTrail log group is the backbone for CloudWatch Metric Filters and Alarms:
  - Account activity (CIS 4.3/4.4/4.5 + more) → `cerpac_cloudtrail_alarms.tf`
  - Infrastructure changes (SG/VPC/S3 policy) → `cerpac_cloudtrail_infra_alarms.tf`
  - Alarm actions publish to the central SNS topic (email/Slack via forwarder)
- GuardDuty findings drive alerts via EventBridge (not from its log group)
- Lambda log groups are primarily for troubleshooting; no alerts attached by default
- Firehose log group (if enabled) helps diagnose delivery issues from WAF → S3

---

## Retention tuning – recommended defaults

- /aws/cloudtrail/production-cerpac-audit-trail → 90 days (compliance + alerting)
- /aws/guardduty/malware-scan-events → 90 days (forensics)
- /aws/lambda/production-cerpac-sns-to-slack → 30–90 days (ops troubleshooting)
- /aws/lambda/production-cerpac-waf-log-router → 14–30 days (ops troubleshooting)

Optional: If you enable Firehose CloudWatch logging in the future, set `/aws/firehose/<stream-name>` retention to ~30 days.

These values balance cost with usefulness. Increase if mandated by compliance.

---

## How to manage retention in Terraform

For service-created log groups (Lambda/Firehose), add explicit `aws_cloudwatch_log_group` resources:

Example: manage Lambda log groups retention

```hcl
resource "aws_cloudwatch_log_group" "lambda_sns_to_slack" {
  name              = "/aws/lambda/${var.env}-cerpac-sns-to-slack"
  retention_in_days = 90

  tags = {
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_log_group" "lambda_waf_log_router" {
  name              = "/aws/lambda/${var.env}-cerpac-waf-log-router"
  retention_in_days = 30

  tags = {
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}
```

Optional example: manage Firehose log group retention (if CloudWatch logging is enabled for Firehose)

```hcl
resource "aws_cloudwatch_log_group" "firehose_waf" {
  name              = "/aws/firehose/cerpac-waf"
  retention_in_days = 30

  tags = {
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}
```

CloudTrail log group retention is already managed in `cerpac_cloud_trail.tf`:

```hcl
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${var.env}-cerpac-audit-trail"
  retention_in_days = 90
}
```

---

## Operational guidance

- Access: CloudWatch Logs → Log groups → select group → Search for patterns or create metric filters
- Least privilege: restrict who can read CloudTrail and Lambda logs (they may include sensitive context)
- Cost watch: high-ingest groups (CloudTrail, Firehose) can grow—periodically review retention and volume
- Incident response: see `documentations/incident_response_plan.md` for what to capture and how to escalate

---

## References (in repo)

- CloudTrail + CW Logs wiring: `production-infrastructure/cerpac_cloud_trail.tf`
- CloudTrail alarms (baseline CIS): `production-infrastructure/cerpac_cloudtrail_alarms.tf`
- CloudTrail alarms (infra change): `production-infrastructure/cerpac_cloudtrail_infra_alarms.tf`
- EventBridge + SNS alerting: `production-infrastructure/cerpac_security_alerting.tf`
- Slack forwarder Lambda: `production-infrastructure/cerpac_security_slack_lambda.tf`
- WAF + Firehose + Log Router: `production-infrastructure/cerpac_waf*.tf`
