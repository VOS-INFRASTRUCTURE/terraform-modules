################################################################################
# AWS SECURITY HUB – CORE ENABLEMENT AND STANDARDS
# Purpose: Enable Security Hub and subscribe to core standards for continuous security posture.
# Toggle: Controlled via var.enable_security_hub
################################################################################

################################################################################
# ACTIVATE SECURITY HUB FOR THIS ACCOUNT & REGION
#
# ⚠️ IMPORTANT: Security Hub MUST be manually enabled before using this module!
#
# The aws_securityhub_account resource is deprecated and no longer functional.
# AWS now requires Security Hub to be enabled manually via AWS Console.
#
# Steps to Enable Security Hub:
# ──────────────────────────────
# 1. Go to AWS Console → Security Hub
# 2. Click "Enable Security Hub"
# 3. Choose your capabilities (Essential, Threat Analytics, etc.)
# 4. Choose regions (Enable in all regions recommended)
# 5. Click "Enable Security Hub"
#
# After enabling, this module will:
# ✅ Subscribe to security standards (AWS Foundational, CIS, Resource Tagging)
# ✅ Enable GuardDuty integration
# ✅ Configure EventBridge findings routing to SNS
#
# The module does NOT:
# ❌ Enable Security Hub itself (must be done manually)
# ❌ Configure Security Hub capabilities (Essential, Threat Analytics, etc.)
# ❌ Configure cross-region aggregation
#
# To check if Security Hub is enabled:
#   aws securityhub describe-hub --region <your-region>
#
# To enable via AWS CLI (if you prefer):
#   aws securityhub enable-security-hub \
#     --enable-default-standards \
#     --region <your-region>
################################################################################

################################################################################
# STANDARDS SUBSCRIPTIONS
# Each standard can be individually enabled/disabled via variables:
# - var.enable_aws_foundational_standard (AWS Foundational Security Best Practices v1.0.0)
# - var.enable_cis_standard (CIS AWS Foundations Benchmark v5.0.0)
# - var.enable_resource_tagging_standard (AWS Resource Tagging Standard v1.0.0)
#
# Note: Security Hub must be enabled (var.enable_security_hub = true) for any
#       standards to be subscribed.
################################################################################

# AWS Foundational Security Best Practices
resource "aws_securityhub_standards_subscription" "aws_foundational" {
  count = var.enable_security_hub && var.enable_aws_foundational_standard ? 1 : 0

  # Security Hub must be enabled manually before this works
  # arn:aws:securityhub:<region>::standards/aws-foundational-security-best-practices/v/1.0.0
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"
}

# CIS AWS Foundations Benchmark v5.0.0
resource "aws_securityhub_standards_subscription" "cis_v500" {
  count = var.enable_security_hub && var.enable_cis_standard ? 1 : 0

  # Security Hub must be enabled manually before this works
  # arn:aws:securityhub:<region>::standards/cis-aws-foundations-benchmark/v/5.0.0
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/cis-aws-foundations-benchmark/v/5.0.0"
}

# AWS Resource Tagging Standard v1.0.0
resource "aws_securityhub_standards_subscription" "resource_tagging" {
  count = var.enable_security_hub && var.enable_resource_tagging_standard ? 1 : 0

  # Security Hub must be enabled manually before this works
  # arn:aws:securityhub:<region>::standards/aws-resource-tagging-standard/v/1.0.0
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-resource-tagging-standard/v/1.0.0"
}

################################################################################
# INTEGRATIONS – PRODUCT SUBSCRIPTIONS
# GuardDuty integration allows its findings to appear in Security Hub.
# Toggle: var.enable_guardduty_integration (requires GuardDuty to be enabled)
################################################################################

resource "aws_securityhub_product_subscription" "guardduty" {
  count = var.enable_security_hub && var.enable_guardduty_integration ? 1 : 0

  # Security Hub must be enabled manually before this works
  # arn:aws:securityhub:<region>::product/aws/guardduty
  product_arn = "arn:aws:securityhub:${data.aws_region.current.name}::product/aws/guardduty"
}
