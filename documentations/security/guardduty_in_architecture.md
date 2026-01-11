# Amazon GuardDuty in CERPAC Production – Role, Flow, and Operations

This document explains how GuardDuty fits into the production security architecture, what data it analyzes, how alerts flow to the team, and how it supports compliance. It includes a 2D diagram, quick-look tables, and references to the exact Terraform code used here.

---

## Why GuardDuty (in one minute)

- Purpose: Managed threat detection for your AWS account and workloads
- What it does: Continuously analyzes AWS signals (CloudTrail, VPC Flow Logs, DNS, S3 data events, Malware Protection) to detect suspicious activity
- Outcomes: Actionable “Findings” (with severity) that we route to Security Hub and notify via EventBridge → SNS (Email/Slack)
- Value add: No agents to manage; minimal overhead; constantly updated detections from AWS threat intel

Terraform source: `production-infrastructure/cerparc_guard_duty.tf`

---

## 2D Architecture Flow (GuardDuty’s place)

```
┌──────────────────────────────────────────────────────────────┐
│                  CloudTrail  •  VPC Flow Logs  •  DNS        │
│                  S3 Data Events  •  Malware Protection       │
└───────────────┬───────────────────────────┬──────────────────┘
                │                           │
                ▼                           ▼
      ┌──────────────────┐          ┌──────────────────┐
      │  GuardDuty       │          │  S3 Protection   │
      │  (Detector)      │          │  (Data events)   │
      └─────────┬────────┘          └─────────┬────────┘
                │ Findings (severity, type, evidence)
                ▼
      ┌───────────────────────────┐
      │  Security Hub (standards)│
      │  + GuardDuty integration │
      └─────────┬────────────────┘
                │
                │ EventBridge Rules (High/Critical, Failed controls)
                ▼
      ┌───────────────────────────┐
      │          SNS              │
      │  Email  •  Slack (Lambda) │
      └─────────┬────────────────┘
                │
                ▼
           Security Team
```

- Findings live in GuardDuty and are aggregated in Security Hub
- High/Critical findings are routed to your notification channels within minutes
- All of this is managed as code and tied to your CloudTrail/CW Logs backbone

---

## What GuardDuty analyzes here

| Data Source | Enabled | Details | Notes |
|-------------|---------|---------|-------|
| CloudTrail Management Events | ✅ Yes | API activity across the account | Enabled by the GuardDuty service itself |
| VPC Flow Logs | ✅ Yes | Network metadata (source/dest, ports) | Used to detect port scans, brute force, exfiltration |
| DNS Query Logs | ✅ Yes | DNS lookups from your resources | Detects suspicious domains and C2 traffic |
| S3 Data Events | ✅ Yes | Suspicious object-level access patterns | Enabled in our Terraform (see file below) |
| Malware Protection | ✅ Yes (events present) | Scan events for potential malware | Log group: `/aws/guardduty/malware-scan-events` (diagnostic) |

Terraform file: `production-infrastructure/cerparc_guard_duty.tf`

---

## How alerts are routed (and who gets them)

- Step 1: GuardDuty creates a Finding (with severity 0.1–8.9)
- Step 2: Security Hub ingests the finding automatically
- Step 3: EventBridge rules match High/Critical severities (≥ 7)
- Step 4: Alerts are sent via SNS to:
  - Email: `security_alert_email` (from tfvars)
  - Slack: via Lambda forwarder if `security_slack_webhook_url` is present

Terraform files:
- EventBridge + SNS: `production-infrastructure/cerpac_security_alerting.tf`
- Slack forwarder Lambda: `production-infrastructure/cerpac_security_slack_lambda.tf`

### Severity routing table

| Severity | GuardDuty Score | Routed? | Channel |
|----------|------------------|---------|---------|
| Critical | ≥ 8.0 | ✅ Yes | SNS → Email/Slack |
| High | ≥ 7.0 and < 8.0 | ✅ Yes | SNS → Email/Slack |
| Medium | ≥ 4.0 and < 7.0 | ⏳ Optional (not currently) | N/A |
| Low/Informational | < 4.0 | ❌ No (review in console/Security Hub) | N/A |

---

## Feature matrix (what’s on and where it shows up)

| Feature | Status | Evidence/Location | Notes |
|---------|--------|-------------------|-------|
| GuardDuty Detector | ✅ Enabled | `cerparc_guard_duty.tf` | 15-minute publishing |
| S3 Protection | ✅ Enabled | `cerparc_guard_duty.tf` | Detects suspicious S3 access patterns |
| Security Hub integration | ✅ Enabled | `cerparc_security_hub.tf` + Product subscription | Findings auto-aggregated |
| EventBridge alerts (High/Critical) | ✅ Enabled | `cerpac_security_alerting.tf` | SNS topic + email + optional Slack |
| Slack forwarding | ✅ Optional | `cerpac_security_slack_lambda.tf` | On if webhook set in tfvars |
| Malware scan events | ✅ Present | `/aws/guardduty/malware-scan-events` | Used for forensics; no direct alerting |

---

## Ops: triage, tune, and test

Triage
- Start in Security Hub: filter by Product = GuardDuty, severity High/Critical
- Use console links in alerts to open the finding detail
- Correlate with CloudTrail events and VPC Flow Logs (GuardDuty provides context)

Tuning (noise reduction)
- Suppression rules in GuardDuty (console/API) for known benign sources
- Narrow Security Hub or EventBridge rules if you add more channels
- Keep High/Critical routed; consider Medium routing if needed

Testing
- Use GuardDuty “Generate sample findings” in the AWS Console to validate the alert path
- Confirm SNS email subscription is confirmed (you will not receive emails otherwise)
- For Slack: verify Lambda forwarder and webhook are present

---

## Compliance & architecture fit

| Framework | Control Area | GuardDuty’s Contribution |
|----------|---------------|--------------------------|
| CIS AWS Foundations | 3.x (Logging/Monitoring) | Continuous threat detection, feeds Security Hub |
| AWS Foundational SBP | Detective Controls | Findings mapped to detective controls automatically |
| NIST CSF | Detect (DE) | Anomalies and events (DE.AE), Security continuous monitoring (DE.CM) |

Architectural fit:
- Complements AWS WAF (prevent at edge) with detection in the account/VPC
- Runs on top of the CloudTrail + VPC Flow Logs + DNS backbone you already operate
- Integrated into the same alerting bus (EventBridge + SNS) as Security Hub

---

## References (in this repo)

- GuardDuty config: `production-infrastructure/cerparc_guard_duty.tf`
- Security Hub standards: `production-infrastructure/cerparc_security_hub.tf`
- Alerting rules and SNS: `production-infrastructure/cerpac_security_alerting.tf`
- Slack forwarder: `production-infrastructure/cerpac_security_slack_lambda.tf`
- CloudTrail backbone: `production-infrastructure/cerpac_cloud_trail.tf`

---

## FAQ

- Does GuardDuty store logs?  
  No. It analyzes AWS data sources and produces findings. The underlying logs (CloudTrail, VPC Flow Logs, DNS) are AWS-managed; CloudTrail is stored to S3 and mirrored to CloudWatch Logs in this environment.

- Why don’t we alert on Medium findings?  
  To reduce noise initially; you can expand routing later. You can still review all findings in Security Hub.

- Do we pay a lot for GuardDuty?  
  Pricing is pay-per-GB analyzed per data source. With CloudTrail free management events and moderate traffic, typical monthly cost is modest. Monitor in Cost Explorer.

