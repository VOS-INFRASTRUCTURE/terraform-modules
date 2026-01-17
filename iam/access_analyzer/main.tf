################################################################################
# IAM Access Analyzer (Security Control IAM.21)
#
# Purpose: Enable IAM Access Analyzer to continuously monitor and analyze
#          resource-based policies for external access permissions.
#
# Security Hub Control: IAM.21
# Severity: MEDIUM
# Standard: AWS Foundational Security Best Practices v1.0.0
#
# What It Does:
# - Analyzes resource-based policies (S3, IAM, KMS, Lambda, SQS, SNS, etc.)
# - Identifies resources shared with external AWS accounts
# - Detects publicly accessible resources
# - Generates findings for cross-account access
# - Integrates with Security Hub for centralized alerts
#
# Risk if Not Enabled:
# - No visibility into external resource access
# - Potential data leaks from misconfigured policies
# - Compliance violations (GDPR, PCI DSS, SOC 2)
# - Difficult to audit cross-account permissions
#
# Compliance Frameworks:
# - AWS Foundational Security Best Practices
# - CIS AWS Foundations Benchmark
# - NIST CSF
# - PCI DSS
# - SOC 2
# - GDPR
#
# Cost: $0 (free for standard account-level analyzer)
################################################################################

################################################################################
# Data Sources
################################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

################################################################################
# IAM Access Analyzer
################################################################################

resource "aws_accessanalyzer_analyzer" "this" {
  count = var.enable_access_analyzer ? 1 : 0

  analyzer_name = "${var.env}-${var.project_id}-access-analyzer"
  type          = var.analyzer_type

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-access-analyzer"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "IAM-Access-Analysis"
      Compliance  = "SecurityHub-IAM.21"
    },
    var.tags
  )
}

################################################################################
# Outputs
################################################################################

output "access_analyzer" {
  description = "IAM Access Analyzer configuration and status"
  value = {
    # Whether Access Analyzer is enabled
    enabled = var.enable_access_analyzer

    # Analyzer details (null if not enabled)
    analyzer_name = var.enable_access_analyzer ? aws_accessanalyzer_analyzer.this[0].analyzer_name : null
    analyzer_arn  = var.enable_access_analyzer ? aws_accessanalyzer_analyzer.this[0].arn : null
    analyzer_type = var.enable_access_analyzer ? aws_accessanalyzer_analyzer.this[0].type : null
    analyzer_id   = var.enable_access_analyzer ? aws_accessanalyzer_analyzer.this[0].id : null
  }
}

