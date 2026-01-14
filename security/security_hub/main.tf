################################################################################
# AWS Security Hub - Centralized Security Monitoring & Alerting
# Go to https://eu-west-2.console.aws.amazon.com/securityhub/home?region=eu-west-2#/onboard
# Enable AWS Security Hub CSPM
#
# Purpose: Comprehensive security monitoring module that provides:
#   - AWS Security Hub (standards-based security posture management)
#   - EventBridge routing to external SNS topic
#   - GuardDuty findings integration
#
# Components (see individual .tf files for details):
#   1. security_hub.tf                              - Security Hub enablement & standards
#   2. security_hub_alerting.tf                     - EventBridge routing to SNS
#
# Architecture:
#   Security Hub ← GuardDuty/Config/Inspector findings
#   Security Hub → EventBridge → SNS (external, from security_notification module)
#
# Note: This module does NOT create SNS topics or Lambda functions.
#       Use the security_notification module to create:
#         - SNS topic for security alerts
#         - Lambda for Slack notifications (optional)
#         - Lambda for SES email handler (optional)
#       Then pass the SNS topic ARN to this module via security_alerts_sns_topic_arn
#
# Cost Impact:
#   - Security Hub: ~$0.0010 per finding ingested (first 10k free)
#   - EventBridge rules: Free
#   Typical: $5-15/month for production (excluding SNS/Lambda costs)
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
# - security_hub_alerting.tf: EventBridge rules + SNS topic policy
#
# This module expects an external SNS topic ARN to be provided via
# var.security_alerts_sns_topic_arn (typically from security_notification module)
################################################################################

