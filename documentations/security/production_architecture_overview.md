# CERPAC Production Architecture – 2D Overview

This high-level 2D chart illustrates the full production infrastructure and the security controls in place, with references to where each component is defined.

---

## 2D Architecture Chart (Layers + Data Flow)

```
                            Internet Clients
                                   |
                                   v
+--------------------------------------------------------------------------+
|                         AWS Route53 (DNS)                                |
|   - cerpac.vosapps.com                                                  |
+--------------------------------------------------------------------------+
                                   |
                                   v
+--------------------------------------------------------------------------+
|                  AWS Application Load Balancer (ALB)                     |
|   - Public ALB                                                           |
|   - TLS 1.2+                                                             |
|   - Target groups → EC2 apps                                             |
|                                                                          |
|   Security:                                                              |
|   - AWS WAF (Web ACL) [CommonRuleSet, KnownBadInputs, SQLi, IP Reputation]|
|   - Rate limiting per IP                                                 |
|   - WAF logging → Kinesis Firehose → Lambda → S3 (allowed/blocked/errors)|
+--------------------------------------------------------------------------+
                                   |
                                   v
+--------------------------------------------------------------------------+
|                          VPC (Production)                                |
|   - CIDR 10.2.0.0/16                                                     |
|   - Public subnets (ALB)                                                 |
|   - Private subnets (EC2 apps, DBs)                                      |
|   - NAT/IGW as needed                                                    |
|                                                                          |
|   Security:                                                              |
|   - Security Groups (least privilege)                                    |
|   - NACLs (as required)                                                  |
|   - Flow Logs (consumed by GuardDuty)                                    |
+--------------------------------------------------------------------------+
             |                                   |                     
             v                                   v                     
+-------------------------------+    +-------------------------------+   
|         EC2: Client App       |    |        EC2: Admin App        |   
|  - t3/c6a instance types      |    |  - t3 instance               |   
|  - Private subnet             |    |  - Private subnet            |   
|                               |    |                               |   
| Security:                     |    | Security:                     |   
|  - SG: ALB→App only           |    |  - SG: ALB→Admin only         |   
+-------------------------------+    +-------------------------------+   
             |                                   |                     
             v                                   v                     
+-------------------------------+    +-------------------------------+   
|       EC2: Insurance App      |    |       EC2: External Frontends |   
|  - t3a instance               |    |  - External sites (as needed) |   
|  - Private subnet             |    |                                |   
+-------------------------------+    +-------------------------------+   

                             Data Tier (Backups + DB)
                             -------------------------
+--------------------------------------------------------------------------+
|                         S3 Buckets (Data & Backups)                      |
|  - production-cerpac-cloud-storage-03-api                                |
|  - production-cerpac-cloud-storage-04-insurance                          |
|  - production-cerpac-cloud-storage-mysql-db-backup-01                    |
|  - production-cerpac-cloud-storage-postgres-db-backup-01                 |
|  - Encryption at rest (SSE-S3 AES-256), versioning where applicable      |
+--------------------------------------------------------------------------+

+-------------------------------+    +-------------------------------+   
|          EC2: PostgreSQL      |    |            EC2: MySQL         |   
|  - t3a.medium                 |    |  - t3a.medium                 |   
|  - Private subnet             |    |  - Private subnet             |   
|  - SG: app-only access        |    |  - SG: app-only access        |   
+-------------------------------+    +-------------------------------+   

                             Observability & Security
                             ------------------------
+--------------------------------------------------------------------------+
|                        Logging & Alerting Backbone                        |
|                                                                          |
|  CloudTrail (Multi-Region)                                               |
|   - S3: production-cerpac-cloudtrail-logs                                |
|   - CloudWatch Log Group: /aws/cloudtrail/production-cerpac-audit-trail  |
|   - Metric filters + alarms (CIS): Unauthorized API, Root usage,        |
|     Console login w/o MFA, IAM policy changes, CloudTrail changes, KMS   |
|     CMK disable/delete, AWS Config changes                               |
|                                                                          |
|  EventBridge + SNS                                                       |
|   - GuardDuty (High/Critical) → SNS → Email (+ Slack)                    |
|   - Security Hub FAILED controls → SNS → Email (+ Slack)                 |
|                                                                          |
|  Lambda: SNS→Slack forwarder                                             |
|   - Log Group: /aws/lambda/production-cerpac-sns-to-slack                |
|                                                                          |
|  GuardDuty                                                               |
|   - Detector: 15-min publishing                                          |
|   - S3 protection enabled                                                |
|                                                                          |
|  Security Hub                                                            |
|   - Standards: AWS Foundational v1.0.0, CIS v5.0.0                        |
|   - Product subscription: GuardDuty                                      |
|                                                                          |
|  AWS Config                                                              |
|   - S3: production-cerpac-aws-config-logs                                |
|   - Continuous configuration recording                                   |
+--------------------------------------------------------------------------+

+--------------------------------------------------------------------------+
|                         WAF Logging Pipeline                              |
|  ALB → AWS WAF → Kinesis Firehose → Lambda (log router) → S3             |
|  - S3 Bucket: production-cerpac-app-alb-waf-logs                          |
|  - Dynamic partitions: allowed/, blocked/, errors/                        |
|  - Lifecycle: allowed 7d, blocked 90d, errors 7d                          |
+--------------------------------------------------------------------------+
```

---

## Security Controls at a Glance

- Edge: AWS WAF (Managed Rule Groups + Rate limiting), TLS 1.2+
- Network: VPC isolation, SG least-privilege, NACLs as needed
- Data: SSE-S3 AES-256, EBS default encryption, backups in S3
- Audit: CloudTrail (S3 + CloudWatch Logs), log validation, multi-region
- Detection: GuardDuty (base + S3), Security Hub (standards enabled)
- Alerting: EventBridge → SNS → Email (+ Slack via Lambda)
- WAF Logs: Firehose + Lambda routing to S3 folders (allowed/blocked/errors)

---

## Where Things Live (Terraform references)

- WAF + ALB: `production-infrastructure/cerpac_waf.tf`, `cerpac_alb.tf`
- WAF logging pipeline: `cerpac_waf_logging.tf`, `cerpac_waf_firehose.tf`, `cerpac_waf_lambda.tf`
- CloudTrail: `cerpac_cloud_trail.tf`
- CloudTrail alarms (baseline CIS): `cerpac_cloudtrail_alarms.tf`
- CloudTrail alarms (infra change): `cerpac_cloudtrail_infra_alarms.tf`
- EventBridge + SNS: `cerpac_security_alerting.tf`
- Slack forwarder Lambda: `cerpac_security_slack_lambda.tf`
- GuardDuty: `cerparc_guard_duty.tf`
- Security Hub: `cerparc_security_hub.tf`
- AWS Config: `cerpac_aws_config.tf`
- EC2 apps & DBs: `cerpac_client_ec2.tf`, `cerpac_admin_ec2.tf`, `cerpac_insurance_ec2.tf.bak`, `cerpac_postgre_db_ec2.tf`, `cerpac_mysql_db_ec2.tf.bak`
- S3 buckets: `s3-cloud-storage-*.tf`

---

## Notes

- Alerting enablement is automatic when Email or Slack webhook is provided in `security_alerting` tfvars; CloudTrail alarms toggles live under `security_alerting` too.
- Security Hub re-evaluates controls periodically (12–24h) and will flip to PASSED when filters+alarms are detected.
- CloudTrail → CloudWatch Logs wiring must be healthy for alarms to pass.

---

## Legend (Symbols)

- Boxes: AWS resources or service layers
- Annotations: security controls and logging
- Arrows: data/control flow between layers


