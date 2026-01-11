################################################################################
# AWS WAF (Web Application Firewall) Module
#
# Purpose: Protect web applications from common web exploits and attacks
#          using AWS WAFv2 with managed rule groups and custom rules.
#
# Components:
#   1. waf.tf                    - Web ACL with managed rule groups
#   2. waf_logging.tf            - S3 bucket for WAF logs
#   3. waf_firehose.tf           - Kinesis Firehose delivery stream
#   4. waf_firehose_iam.tf       - IAM roles for Firehose
#   5. waf_log_router_lambda.tf  - Lambda for intelligent log routing
#   6. bucket.tf                 - S3 bucket configuration (if separate)
#
# Features:
#   - AWS Managed Rule Groups (OWASP Top 10, SQL injection, XSS, etc.)
#   - Rate limiting (DDoS protection)
#   - Intelligent log routing (blocked vs allowed requests)
#   - Cost-optimized log retention (90 days blocked, 7 days allowed)
#   - Real-time metrics and CloudWatch dashboards
#   - Kinesis Firehose for log delivery
#
# Protection Layers:
#   Phase 1: Baseline protection (enabled by default)
#     - Core Rule Set (OWASP Top 10)
#     - Known Bad Inputs
#     - SQL Injection
#     - IP Reputation List
#     - Rate Limiting
#
#   Phase 2: Stack-specific rules (conditional)
#     - WordPress, PHP, Linux, Windows rules
#     - Enable based on application stack
#
#   Phase 3: Advanced protection (paid)
#     - Bot Control ($10/month + usage)
#     - Account Takeover Prevention ($10/month + usage)
#     - Account Creation Fraud Prevention ($10/month + usage)
#
# WCU (Web ACL Capacity Units) Management:
#   - Maximum: 1500 WCU per Web ACL
#   - Current baseline: ~1325 WCU
#   - Always calculate total before adding rules
#
# Cost Impact:
#   - WAF: $5/month + $1 per million requests
#   - Managed rules: Free (AWS managed)
#   - Bot Control: $10/month + $1 per million requests
#   - ATP/ACFP: $10/month + $1 per 1,000 login attempts
#   - Logging: S3 storage + Firehose delivery (~$2-5/month)
#   Typical production: $10-30/month (without paid features)
################################################################################

################################################################################
# Data Sources
################################################################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

################################################################################
# Locals
################################################################################

locals {
  resource_prefix = var.env
  cerpac_frontend_alb_key_name = var.alb_name != null ? var.alb_name : "app-alb"
}

################################################################################
# NOTE: All module logic is split into separate files:
#
# - waf.tf: Web ACL definition with all managed rule groups
# - waf_logging.tf: S3 bucket for WAF logs with lifecycle policies
# - waf_firehose.tf: Kinesis Firehose delivery stream
# - waf_firehose_iam.tf: IAM roles and policies for Firehose
# - waf_log_router_lambda.tf: Lambda function for log routing
#
# This separation improves maintainability and makes it easier to enable/disable
# specific components via variables.
################################################################################

