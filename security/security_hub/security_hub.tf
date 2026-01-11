################################################################################
# AWS SECURITY HUB – CORE ENABLEMENT AND STANDARDS
# Purpose: Enable Security Hub and subscribe to core standards for continuous security posture.
# Toggle: Controlled via var.enable_security_hub
################################################################################

data "aws_region" "current" {}

# Optional shared tags (if you later add taggable SH resources)
locals {
  sh_tags = {
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

################################################################################
# ACTIVATE SECURITY HUB FOR THIS ACCOUNT & REGION
# Notes:
# - Creates/activates the Security Hub service for the current account/region.
# - Required before subscribing to standards or products.
################################################################################

resource "aws_securityhub_account" "this" {
  count = var.enable_security_hub ? 1 : 0
}

################################################################################
# STANDARDS SUBSCRIPTIONS
# References:
# - AWS Foundational Security Best Practices v1.0.0
# - CIS AWS Foundations Benchmark v5.0.0
# - AWS Resource Tagging Standard v1.0.0
# ARN patterns resolve region dynamically via data.aws_region.current.name
################################################################################

# AWS Foundational Security Best Practices
resource "aws_securityhub_standards_subscription" "aws_foundational" {
  count = var.enable_security_hub ? 1 : 0

  depends_on = [aws_securityhub_account.this]

  # arn:aws:securityhub:<region>::standards/aws-foundational-security-best-practices/v/1.0.0
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"
}

# CIS AWS Foundations Benchmark v5.0.0
resource "aws_securityhub_standards_subscription" "cis_v500" {
  count = var.enable_security_hub ? 1 : 0

  depends_on = [aws_securityhub_account.this]

  # arn:aws:securityhub:<region>::standards/cis-aws-foundations-benchmark/v/5.0.0
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/cis-aws-foundations-benchmark/v/5.0.0"
}

# AWS Resource Tagging Standard v1.0.0
resource "aws_securityhub_standards_subscription" "resource_tagging" {
  count = var.enable_security_hub ? 1 : 0

  depends_on = [aws_securityhub_account.this]

  # arn:aws:securityhub:<region>::standards/aws-resource-tagging-standard/v/1.0.0
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-resource-tagging-standard/v/1.0.0"
}

################################################################################
# INTEGRATIONS – PRODUCT SUBSCRIPTIONS
# GuardDuty integration allows its findings to appear in Security Hub.
################################################################################

resource "aws_securityhub_product_subscription" "guardduty" {
  count = var.enable_security_hub ? 1 : 0

  depends_on = [aws_securityhub_account.this]

  # arn:aws:securityhub:<region>::product/aws/guardduty
  product_arn = "arn:aws:securityhub:${data.aws_region.current.name}::product/aws/guardduty"
}
