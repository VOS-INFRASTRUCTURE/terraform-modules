# AWS CloudTrail - Audit & Compliance Logging

## Overview

AWS CloudTrail is a service that enables governance, compliance, operational auditing, and risk auditing of your AWS account. It records AWS API calls and related events made by or on behalf of your AWS account and delivers log files to an Amazon S3 bucket.

## Purpose

CloudTrail provides a comprehensive audit trail of all activities in your AWS environment, enabling:

- **Security Analysis**: Detect unauthorized access attempts and security incidents
- **Compliance**: Meet regulatory requirements (SOC 2, PCI-DSS, HIPAA, GDPR)
- **Operational Troubleshooting**: Debug service issues by reviewing API call history
- **Risk Auditing**: Identify risky configurations and policy changes
- **Change Tracking**: Monitor who changed what and when
- **Forensic Investigation**: Analyze security incidents with detailed event history

---

## CloudTrail Configuration

### Multi-Region Trail

The CloudTrail is configured as a **multi-region trail**, which means:

- ✅ **Global Coverage**: Captures events from ALL AWS regions
- ✅ **Centralized Logging**: All regional events flow to one S3 bucket
- ✅ **Automatic Region Support**: New regions added by AWS are automatically included
- ✅ **Cost Efficient**: One trail covers entire account (no per-region trails needed)
- ✅ **Compliance Ready**: Ensures no region is left unmonitored

**Trail Name**: `production-cerpac-audit-trail` (or similar for your environment)

---

## Log Storage Architecture

### S3 Bucket for Long-Term Storage

**Bucket Name**: `production-cerpac-cloudtrail-logs`

**Purpose**: Permanent, tamper-proof storage of all CloudTrail events

**Features**:
- **Versioning Enabled**: Protects against accidental deletion or modification
- **Encryption**: Server-side encryption (SSE-S3 or SSE-KMS)
- **Lifecycle Policies**: 
  - Transition to S3 Glacier after 90 days (cost optimization)
  - Retain logs for 7+ years (compliance requirement)
- **Access Logging**: Tracks who accesses the audit logs
- **Bucket Policy**: Restricts access to authorized personnel only

**Log Structure**:
```
s3://production-cerpac-cloudtrail-logs/
  AWSLogs/
    <account-id>/
      CloudTrail/
        <region>/
          <year>/<month>/<day>/
            <account-id>_CloudTrail_<region>_<timestamp>.json.gz
```

**Example Event**:
```json
{
  "eventVersion": "1.08",
  "userIdentity": {
    "type": "IAMUser",
    "principalId": "AIDAI...",
    "arn": "arn:aws:iam::123456789012:user/john.doe",
    "accountId": "123456789012",
    "userName": "john.doe"
  },
  "eventTime": "2026-01-11T10:30:00Z",
  "eventSource": "s3.amazonaws.com",
  "eventName": "DeleteBucket",
  "awsRegion": "eu-west-2",
  "sourceIPAddress": "203.0.113.12",
  "userAgent": "aws-cli/2.0",
  "requestParameters": {
    "bucketName": "production-app-data"
  },
  "responseElements": null,
  "requestID": "ABC123...",
  "eventID": "def456...",
  "eventType": "AwsApiCall",
  "recipientAccountId": "123456789012"
}
```

---

### CloudWatch Logs for Real-Time Monitoring

**Log Group Name**: `/aws/cloudtrail/production-cerpac-audit-trail`

**Purpose**: Real-time event analysis and alerting

**Why Both S3 and CloudWatch?**

| Feature | S3 Storage | CloudWatch Logs |
|---------|-----------|-----------------|
| **Retention** | 7+ years (compliance) | 30-90 days (cost optimization) |
| **Access Speed** | Slow (minutes to query) | Fast (real-time streaming) |
| **Use Case** | Long-term audit, forensics | Real-time alerts, dashboards |
| **Cost** | Low ($0.023/GB/month) | Higher ($0.50/GB ingested) |
| **Search** | Athena queries (complex) | Log Insights (fast, SQL-like) |
| **Alerts** | Not real-time | Metric filters + alarms ✅ |

**Retention Policy**: 
- **Recommended**: 90 days (balance between cost and investigation needs)
- After 90 days, use S3 for historical analysis

---

## CIS Benchmark Metric Filters & Alarms

CloudTrail logs are monitored using **metric filters** that detect security-critical events based on the **CIS AWS Foundations Benchmark**. When detected, CloudWatch alarms trigger SNS notifications to security teams.

### 1. Unauthorized API Calls

**What it detects**: API calls that fail due to insufficient permissions

**Why it matters**: May indicate:
- Compromised credentials attempting privilege escalation
- Misconfigured applications
- Insider threats probing for access

**Metric Filter Pattern**:
```
{ ($.errorCode = "*UnauthorizedOperation") || ($.errorCode = "AccessDenied*") }
```

**Alarm Threshold**: ≥ 5 unauthorized calls in 5 minutes

**Response**: Investigate source IP, user identity, and attempted actions

---

### 2. Root Account Usage

**What it detects**: Any activity by the AWS root user

**Why it matters**: 
- Root user has unlimited permissions (can't be restricted)
- Should ONLY be used for account recovery
- Regular use violates security best practices

**Metric Filter Pattern**:
```
{ $.userIdentity.type = "Root" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != "AwsServiceEvent" }
```

**Alarm Threshold**: ≥ 1 root login or API call

**Response**: 
1. Verify if usage was authorized (emergency access)
2. Investigate what actions were taken
3. Enable MFA on root if not already enabled
4. Rotate root password if compromise suspected

---

### 3. Console Sign-in Without MFA

**What it detects**: Users logging into AWS Console without multi-factor authentication

**Why it matters**:
- MFA provides critical second layer of defense
- Stolen passwords alone can't access account
- Compliance requirement for production environments

**Metric Filter Pattern**:
```
{ ($.eventName = "ConsoleLogin") && ($.additionalEventData.MFAUsed != "Yes") }
```

**Alarm Threshold**: ≥ 1 non-MFA login

**Response**:
1. Contact user immediately
2. Enforce MFA policy in IAM
3. Consider revoking access for non-compliant users

---

### 4. IAM Policy Changes

**What it detects**: Modifications to IAM policies, roles, users, or groups

**Why it matters**:
- Policy changes can grant unintended permissions
- Attackers often modify policies for persistence
- Critical for audit trails and compliance

**Metric Filter Pattern**:
```
{
  ($.eventName = PutUserPolicy) ||
  ($.eventName = PutRolePolicy) ||
  ($.eventName = PutGroupPolicy) ||
  ($.eventName = CreatePolicy) ||
  ($.eventName = DeletePolicy) ||
  ($.eventName = CreatePolicyVersion) ||
  ($.eventName = DeletePolicyVersion) ||
  ($.eventName = AttachRolePolicy) ||
  ($.eventName = DetachRolePolicy) ||
  ($.eventName = AttachUserPolicy) ||
  ($.eventName = DetachUserPolicy) ||
  ($.eventName = AttachGroupPolicy) ||
  ($.eventName = DetachGroupPolicy)
}
```

**Alarm Threshold**: ≥ 1 policy change

**Response**: Review change for legitimacy via CloudTrail event details

---

### 5. CloudTrail Configuration Changes

**What it detects**: Modifications to CloudTrail itself (stopping logging, deleting trails)

**Why it matters**:
- Disabling CloudTrail erases audit visibility
- Common attacker tactic to hide tracks
- Critical security control that must be protected

**Metric Filter Pattern**:
```
{
  ($.eventName = CreateTrail) ||
  ($.eventName = UpdateTrail) ||
  ($.eventName = DeleteTrail) ||
  ($.eventName = StartLogging) ||
  ($.eventName = StopLogging)
}
```

**Alarm Threshold**: ≥ 1 CloudTrail change

**Response**: 
1. **Immediate**: Verify if change was authorized
2. If unauthorized: Re-enable CloudTrail immediately
3. Investigate user identity and source IP
4. Review all events between stoppage and restart

---

### 6. KMS CMK Disable/Delete

**What it detects**: Customer Master Keys (CMKs) being disabled or scheduled for deletion

**Why it matters**:
- Disabling CMK makes encrypted data inaccessible
- Can cause production outages (RDS, EBS, S3 encryption)
- May indicate sabotage or accidental misconfiguration

**Metric Filter Pattern**:
```
{
  ($.eventSource = kms.amazonaws.com) &&
  (
    ($.eventName = DisableKey) ||
    ($.eventName = ScheduleKeyDeletion)
  )
}
```

**Alarm Threshold**: ≥ 1 KMS key disable/delete

**Response**:
1. Identify which key was affected
2. Check if encrypted resources are impacted
3. Cancel key deletion if accidental (`CancelKeyDeletion` API)
4. Review who initiated the change

---

### 7. AWS Config Changes

**What it detects**: Modifications to AWS Config (compliance monitoring service)

**Why it matters**:
- AWS Config tracks resource compliance
- Disabling it blinds compliance monitoring
- May hide non-compliant resource changes

**Metric Filter Pattern**:
```
{
  ($.eventSource = config.amazonaws.com) &&
  (
    ($.eventName = StopConfigurationRecorder) ||
    ($.eventName = DeleteDeliveryChannel) ||
    ($.eventName = PutDeliveryChannel) ||
    ($.eventName = PutConfigurationRecorder)
  )
}
```

**Alarm Threshold**: ≥ 1 Config change

**Response**: Verify change authorization and ensure Config remains enabled

---

## Alarm Notification Flow

```
CloudTrail Event
     ↓
CloudWatch Log Group (/aws/cloudtrail/production-cerpac-audit-trail)
     ↓
Metric Filter (e.g., Root Account Usage)
     ↓
CloudWatch Metric (e.g., RootAccountUsageCount)
     ↓
CloudWatch Alarm (State: ALARM when threshold exceeded)
     ↓
SNS Topic (e.g., production-cerpac-security-alerts)
     ↓
Email/SMS to Security Team
```

**SNS Topic Subscribers**:
- Security team email (e.g., security@cerpac.com)
- Incident response Slack channel (via Lambda)
- PagerDuty (for critical alerts)

---

## Cost Breakdown

| Component | Cost (Monthly Estimate) |
|-----------|------------------------|
| CloudTrail (multi-region, 1 trail) | **Free** (first trail is free) |
| S3 Storage (100 GB logs) | $2.30 (Standard), $0.40 (Glacier after 90 days) |
| CloudWatch Logs Ingestion (10 GB/month) | $5.00 |
| CloudWatch Logs Storage (90 days retention) | $3.00 |
| Metric Filters (7 filters) | **Free** |
| CloudWatch Alarms (7 alarms) | $0.70 ($0.10/alarm) |
| SNS Notifications (100/month) | **Free** (first 1,000 free) |
| **TOTAL** | **~$11.40/month** |

**Cost Optimization Tips**:
- Use S3 Lifecycle policies to move old logs to Glacier ($0.004/GB)
- Reduce CloudWatch Logs retention to 30 days if not needed
- Use S3 Intelligent-Tiering for automatic cost optimization

---

## Querying CloudTrail Logs

### Option 1: CloudWatch Logs Insights (Fast, Recent Events)

**Use for**: Last 90 days, real-time troubleshooting

**Example**: Find all EC2 instance terminations by a specific user

```sql
fields @timestamp, userIdentity.userName, requestParameters.instanceId
| filter eventName = "TerminateInstances"
| filter userIdentity.userName = "john.doe"
| sort @timestamp desc
| limit 100
```

### Option 2: Amazon Athena (S3, Historical Analysis)

**Use for**: Long-term forensics, compliance audits

**Setup**:
1. Create Athena table pointing to S3 bucket
2. Run SQL queries across years of logs

**Example**: Find all failed login attempts in 2025

```sql
SELECT
  eventtime,
  useridentity.username,
  sourceipaddress,
  errorcode
FROM cloudtrail_logs
WHERE eventname = 'ConsoleLogin'
  AND errorcode IS NOT NULL
  AND year = '2025'
ORDER BY eventtime DESC;
```

---

## Security Best Practices

### ✅ Implemented

- [x] Multi-region trail enabled
- [x] S3 bucket versioning enabled
- [x] CloudWatch Logs integration
- [x] CIS Benchmark metric filters + alarms
- [x] SNS notifications for security events
- [x] Encryption at rest (S3)

### 🔒 Recommended Enhancements

- [ ] **S3 Object Lock**: Enable WORM (Write Once Read Many) to prevent log tampering
- [ ] **Cross-Account Logging**: Send logs to separate security account
- [ ] **CloudTrail Insights**: Detect unusual API activity patterns (ML-based)
- [ ] **S3 Access Analyzer**: Monitor who accesses audit logs
- [ ] **AWS Security Hub**: Centralize findings from CloudTrail, GuardDuty, Config
- [ ] **Log File Validation**: Enable to detect log tampering via cryptographic hashes

---

## Incident Response Playbook

### Scenario: Alarm Triggered - "Unauthorized API Calls"

**Step 1: Triage (0-5 minutes)**
1. Check SNS notification for alarm details
2. Log into CloudWatch Logs Insights
3. Run query to see recent unauthorized calls:
   ```sql
   fields @timestamp, userIdentity.userName, sourceIPAddress, eventName, errorCode
   | filter errorCode = "AccessDenied" or errorCode = "UnauthorizedOperation"
   | sort @timestamp desc
   | limit 50
   ```

**Step 2: Investigate (5-15 minutes)**
1. Identify the user/role making calls
2. Check source IP (is it expected? VPN? Foreign country?)
3. Review what resources they attempted to access
4. Check if credentials were compromised (leaked keys on GitHub?)

**Step 3: Contain (15-30 minutes)**
- If compromised IAM user: Disable access keys immediately
- If compromised role: Detach policies or delete role
- If unknown IP: Block via Security Group or WAF

**Step 4: Remediate**
- Rotate all credentials for affected user
- Review all actions taken by compromised identity
- Check if any data was exfiltrated
- Update incident response documentation

**Step 5: Post-Incident**
- Conduct root cause analysis
- Update IAM policies to prevent recurrence
- Train team on security best practices

---

## Compliance Mapping

| Regulation | CloudTrail Requirement | Status |
|-----------|----------------------|--------|
| **SOC 2** | Audit logging of all access | ✅ Met |
| **PCI-DSS 10.1** | Audit trail for cardholder data access | ✅ Met |
| **GDPR Article 33** | Detect breaches within 72 hours | ✅ Met (real-time alerts) |
| **HIPAA 164.312(b)** | Audit controls for ePHI access | ✅ Met |
| **ISO 27001 A.12.4.1** | Event logging | ✅ Met |
| **NIST 800-53 AU-2** | Audit events | ✅ Met |

---

## Troubleshooting

### Logs Not Appearing in CloudWatch

**Cause**: CloudTrail → CloudWatch integration not configured

**Fix**:
1. Check CloudTrail settings: Ensure "CloudWatch Logs" section has log group ARN
2. Verify IAM role has `logs:CreateLogStream` and `logs:PutLogEvents` permissions
3. Check CloudWatch Logs for `/aws/cloudtrail/*` log group

### Alarm Not Triggering

**Cause**: Metric filter not matching events

**Fix**:
1. Test metric filter with sample event in CloudWatch Logs Insights
2. Verify metric filter pattern syntax (JSON path)
3. Check alarm threshold (is it too high?)
4. Ensure SNS topic has valid subscribers

### High CloudWatch Costs

**Cause**: Large volume of logs (VPC Flow Logs, Lambda, etc.)

**Fix**:
1. Reduce retention period (90 days → 30 days)
2. Export old logs to S3 before deletion
3. Filter out noisy events (e.g., health checks, read-only APIs)

---

## Related Services

- **AWS Config**: Tracks resource configuration changes (complements CloudTrail's API logging)
- **Amazon GuardDuty**: Threat detection using CloudTrail events + ML
- **AWS Security Hub**: Centralized security findings dashboard
- **VPC Flow Logs**: Network traffic logging (layer 3/4)
- **S3 Access Logs**: Object-level access tracking

---

## Summary

CloudTrail is the **cornerstone of AWS security monitoring**, providing:

✅ **Complete audit trail** of all AWS account activity  
✅ **Real-time alerting** on security-critical events  
✅ **Compliance evidence** for audits and regulations  
✅ **Forensic capabilities** for incident investigation  
✅ **Cost-effective** (~$11/month for comprehensive monitoring)

**Key Takeaway**: CloudTrail is NOT optional for production environments. It's your "black box" recorder for AWS—essential for security, compliance, and operational excellence.

---

**Last Updated**: January 11, 2026  
**Maintained By**: Security Team  
**Review Cycle**: Quarterly

