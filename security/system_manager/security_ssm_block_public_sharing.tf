################################################################################
# SSM Document Public Sharing Block (Security Control SSM.7)
#
# Purpose: Block public sharing of AWS Systems Manager (SSM) documents at the
#          account level to prevent unauthorized access to automation workflows.
#
# Security Hub Control: SSM.7
# Severity: CRITICAL
# Standard: AWS Foundational Security Best Practices v1.0.0
#
# Risk if Not Enabled:
# - SSM documents could be shared publicly, exposing automation procedures
# - Malicious actors could discover and exploit your automation workflows
# - Sensitive configuration details might be leaked
#
# Compliance Frameworks:
# - AWS Foundational Security Best Practices
# - CIS AWS Foundations Benchmark
# - NIST CSF
# - ISO 27001
#
# Cost: $0 (free security configuration)
################################################################################

resource "aws_ssm_service_setting" "block_public_sharing" {
  count = var.enable_ssm_public_sharing_block ? 1 : 0

  setting_id    = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:servicesetting/ssm/documents/console/public-sharing-permission"
  setting_value = "Disable"
}
#
# ################################################################################
# # SSM Automation CloudWatch Logging (Security Control)
# #
# # Purpose: Ensure all SSM Automation executions are logged to CloudWatch
# #          for auditing and compliance.
# #
# # Security Hub Control: securityhub-ssm-automation-logging-enabled
# # Severity: MEDIUM
# # Standard: AWS Foundational Security Best Practices v1.0.0
# ################################################################################
#
# resource "aws_ssm_service_setting" "enable_automation_logging" {
#   count = var.enable_ssm_automation_logging ? 1 : 0
#
#   # This is the service setting ID for SSM Automation logging
#   setting_id    = "/ssm/automation/enable-logging"
#   setting_value = "Enabled"
# }
#

################################################################################
# Data Sources (required for the ARN construction)
################################################################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

################################################################################
# Outputs
################################################################################

output "ssm_security" {
  description = "SSM security settings and status"
  value = {
    # Whether SSM public sharing block is enabled
    enabled = var.enable_ssm_public_sharing_block

    # SSM service setting details (null if not enabled)
    setting_id    = var.enable_ssm_public_sharing_block ? aws_ssm_service_setting.block_public_sharing[0].setting_id : null
    setting_value = var.enable_ssm_public_sharing_block ? aws_ssm_service_setting.block_public_sharing[0].setting_value : null
    status        = var.enable_ssm_public_sharing_block ? aws_ssm_service_setting.block_public_sharing[0].status : null
    arn           = var.enable_ssm_public_sharing_block ? aws_ssm_service_setting.block_public_sharing[0].arn : null
  }
}

#
# ################################################################################
# # Outputs
# ################################################################################
#
# output "ssm_automation_logging" {
#   description = "SSM Automation CloudWatch logging configuration"
#   value = {
#     enabled       = var.enable_ssm_automation_logging
#     setting_id    = var.enable_ssm_automation_logging ? aws_ssm_service_setting.enable_automation_logging[0].setting_id : null
#     setting_value = var.enable_ssm_automation_logging ? aws_ssm_service_setting.enable_automation_logging[0].setting_value : null
#     status        = var.enable_ssm_automation_logging ? aws_ssm_service_setting.enable_automation_logging[0].status : null
#     arn           = var.enable_ssm_automation_logging ? aws_ssm_service_setting.enable_automation_logging[0].arn : null
#   }
# }