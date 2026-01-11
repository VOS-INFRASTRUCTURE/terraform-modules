################################################################################
# AWS Security Hub - Centralized Security Monitoring & Alerting
#
# Purpose: Comprehensive security monitoring module that provides:
#   - AWS Security Hub (standards-based security posture management)
#   - CloudTrail security alarms (CIS benchmark compliance)
#   - Infrastructure change alarms
#   - Automated alerting via SNS and Slack
#   - GuardDuty findings integration
#
# Components (see individual .tf files for details):
#   1. security_hub.tf                              - Security Hub enablement & standards
#   2. security_hub_alerting.tf                     - SNS topic & EventBridge routing
#   3. security_hub_alerting_slack_normalizer_lambda.tf - Lambda for Slack notifications
#   4. trail_security_alarms.tf                     - CIS benchmark alarms
#   5. trail_infra_change_alarms.tf                 - Infrastructure change detection
#
# Architecture:
#   CloudTrail → CloudWatch Logs → Metric Filters → Alarms → SNS
#   Security Hub ← GuardDuty/Config/Inspector findings
#   Security Hub → EventBridge → SNS/Lambda → Slack
#
# Cost Impact:
#   - Security Hub: ~$0.0010 per finding ingested (first 10k free)
#   - CloudWatch Alarms: $0.10 per alarm/month
#   - Lambda invocations: First 1M free, then $0.20 per 1M
#   - SNS: First 1,000 emails free
#   Typical: $15-30/month for production
################################################################################

################################################################################
# Data Sources
################################################################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

################################################################################
# NOTE: All module logic is split into separate files:
#
# - security_hub.tf: AWS Security Hub account + standards subscriptions
# - security_hub_alerting.tf: SNS topic + EventBridge rules
# - security_hub_alerting_slack_normalizer_lambda.tf: Lambda for Slack
# - trail_security_alarms.tf: CIS security alarms (root usage, etc.)
# - trail_infra_change_alarms.tf: Infrastructure change alarms (SG, VPC, etc.)
#
# This separation improves maintainability and makes it easier to enable/disable
# specific components via variables.
################################################################################

