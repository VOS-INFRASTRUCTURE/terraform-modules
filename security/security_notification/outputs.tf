################################################################################
# Security Notification Module Outputs
#
# All outputs consolidated into a single 'security_notification' object
# for easier consumption and cleaner code organization.
#
# Usage:
#   module.security_alerts.security_notification.sns_topic.arn
#   module.security_alerts.security_notification.email.enabled
#   module.security_alerts.security_notification.slack.enabled
################################################################################

output "security_notification" {
  description = "Security notification configuration and resource details"
  value = {
    # ──────────────────────────────────────────────────────────────────────
    # SNS Topic - Central hub for all security alerts
    # ──────────────────────────────────────────────────────────────────────
    sns_topic = {
      arn          = aws_sns_topic.security_alerts.arn
      id           = aws_sns_topic.security_alerts.id
      name         = aws_sns_topic.security_alerts.name
      display_name = aws_sns_topic.security_alerts.display_name
    }

    # ──────────────────────────────────────────────────────────────────────
    # Email Configuration - Email alerting details
    # ──────────────────────────────────────────────────────────────────────
    email = {
      enabled              = var.enable_email_alerts
      basic_sns_enabled    = var.enable_email_alerts && !var.enable_email_handler && var.security_alert_email != null
      ses_handler_enabled  = var.enable_email_handler
      alert_email          = var.enable_email_alerts && !var.enable_email_handler ? var.security_alert_email : null
      ses_from_email       = var.enable_email_handler ? var.ses_from_email : null
      ses_to_emails        = var.enable_email_handler ? var.ses_to_emails : []
      lambda_function_arn  = var.enable_email_handler ? aws_lambda_function.security_email_handler[0].arn : null
      lambda_function_name = var.enable_email_handler ? aws_lambda_function.security_email_handler[0].function_name : null
    }

    # ──────────────────────────────────────────────────────────────────────
    # Slack Configuration - Slack alerting details
    # ──────────────────────────────────────────────────────────────────────
    slack = {
      enabled              = var.enable_slack_alerts
      webhook_configured   = var.enable_slack_alerts && var.security_slack_webhook_url != null
      lambda_function_arn  = var.enable_slack_alerts ? aws_lambda_function.security_alert_normalizer[0].arn : null
      lambda_function_name = var.enable_slack_alerts ? aws_lambda_function.security_alert_normalizer[0].function_name : null
    }

    # ──────────────────────────────────────────────────────────────────────
    # Configuration Summary - Quick reference
    # ──────────────────────────────────────────────────────────────────────
    summary = {
      environment         = var.env
      project_id          = var.project_id
      email_enabled       = var.enable_email_alerts
      slack_enabled       = var.enable_slack_alerts
      total_subscriptions = (
        (var.enable_email_alerts && !var.enable_email_handler && var.security_alert_email != null ? 1 : 0) +
        (var.enable_email_handler ? 1 : 0) +
        (var.enable_slack_alerts ? 1 : 0)
      )
    }
  }
}

################################################################################
# Individual Outputs (for backward compatibility)
################################################################################

output "sns_topic_arn" {
  description = "ARN of the security alerts SNS topic"
  value       = aws_sns_topic.security_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the security alerts SNS topic"
  value       = aws_sns_topic.security_alerts.name
}

