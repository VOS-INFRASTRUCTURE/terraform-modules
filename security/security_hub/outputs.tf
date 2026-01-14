################################################################################
# Security Hub Module Outputs
#
# All outputs are consolidated into a single 'security_hub' object for easier
# consumption and cleaner code organization.
#
# Usage:
#   module.security_hub.security_hub.hub.account_id
#   module.security_hub.security_hub.alerting.sns_topic_arn
#   module.security_hub.security_hub.alarms.security.count
################################################################################

output "security_hub" {
  description = "AWS Security Hub resources and configuration details"
  value = {
    # ──────────────────────────────────────────────────────────────────────
    # Security Hub - Core service and standards
    # ──────────────────────────────────────────────────────────────────────
    hub = var.enable_security_hub ? {
      account_id = data.aws_caller_identity.current.account_id
      region     = data.aws_region.current.name
      enabled    = true

      # Standards subscribed (only shows enabled standards)
      standards = {
        aws_foundational = var.enable_aws_foundational_standard ? aws_securityhub_standards_subscription.aws_foundational[0].standards_arn : null
        cis_benchmark    = var.enable_cis_standard ? aws_securityhub_standards_subscription.cis_v500[0].standards_arn : null
        resource_tagging = var.enable_resource_tagging_standard ? aws_securityhub_standards_subscription.resource_tagging[0].standards_arn : null
      }

      # Product integrations (only shows enabled integrations)
      products = {
        guardduty = var.enable_guardduty_integration ? aws_securityhub_product_subscription.guardduty[0].product_arn : null
      }
    } : null

    # ──────────────────────────────────────────────────────────────────────
    # Alerting - EventBridge routing to external SNS topic
    # ──────────────────────────────────────────────────────────────────────
    alerting = var.enable_security_alerting ? {
      sns_topic_arn      = var.security_alerts_sns_topic_arn
      sns_topic_name     = split(":", var.security_alerts_sns_topic_arn)[5]  # Extract topic name from ARN

      eventbridge = {
        rule_name = aws_cloudwatch_event_rule.securityhub_findings[0].name
        rule_arn  = aws_cloudwatch_event_rule.securityhub_findings[0].arn
      }

      # Note: SNS topic, Slack Lambda, and Email Lambda are managed by
      #       the security_notification module, not this module
    } : null

    # ──────────────────────────────────────────────────────────────────────
    # Configuration Summary - Quick reference
    # ──────────────────────────────────────────────────────────────────────
    summary = {
      module_enabled                 = true
      environment                    = var.env
      project_id                     = var.project_id

      # Security Hub configuration
      security_hub_enabled           = var.enable_security_hub
      aws_foundational_enabled       = var.enable_aws_foundational_standard
      cis_benchmark_enabled          = var.enable_cis_standard
      resource_tagging_enabled       = var.enable_resource_tagging_standard
      guardduty_integration_enabled  = var.enable_guardduty_integration

      # Alerting configuration
      security_alerting_enabled      = var.enable_security_alerting
      sns_topic_arn                  = var.enable_security_alerting ? var.security_alerts_sns_topic_arn : null

      # Totals
      total_standards_enabled        = (
        (var.enable_aws_foundational_standard ? 1 : 0) +
        (var.enable_cis_standard ? 1 : 0) +
        (var.enable_resource_tagging_standard ? 1 : 0)
      )
    }
  }
}

