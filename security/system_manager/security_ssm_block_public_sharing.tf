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

