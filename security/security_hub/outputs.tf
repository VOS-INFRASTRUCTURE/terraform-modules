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
    # Alerting - SNS topic and EventBridge routing
    # ──────────────────────────────────────────────────────────────────────
    alerting = var.enable_security_alerting ? {
      sns_topic_arn      = aws_sns_topic.security_alerts[0].arn
      sns_topic_name     = aws_sns_topic.security_alerts[0].name
      email_subscription = var.security_alert_email != null ? var.security_alert_email : null

      eventbridge = {
        rule_name = aws_cloudwatch_event_rule.securityhub_findings[0].name
        rule_arn  = aws_cloudwatch_event_rule.securityhub_findings[0].arn
      }

      # Slack Lambda normalizer (if Slack webhook configured)
      slack_lambda = var.security_slack_webhook_url != null ? {
        function_name = aws_lambda_function.security_alert_normalizer.function_name
        function_arn  = aws_lambda_function.security_alert_normalizer.arn
        role_arn      = aws_iam_role.security_alert_lambda_role.arn
      } : null

      # Email Lambda handler (if SES configured)
      email_lambda = var.enable_email_handler ? {
        function_name = aws_lambda_function.security_email_handler[0].function_name
        function_arn  = aws_lambda_function.security_email_handler[0].arn
        role_arn      = aws_iam_role.security_email_lambda_role[0].arn
        from_email    = var.ses_from_email
        to_emails     = var.ses_to_emails
      } : null
    } : null

    # ──────────────────────────────────────────────────────────────────────
    # CloudTrail Security Alarms - CIS benchmark compliance
    # ──────────────────────────────────────────────────────────────────────
    alarms = {
      security = var.enable_cloudtrail_security_alarms ? {
        count = 5  # Number of security alarms configured

        alarms = {
          unauthorized_api_calls = aws_cloudwatch_metric_alarm.unauthorized_api_calls[0].alarm_name
          root_account_usage     = aws_cloudwatch_metric_alarm.root_account_usage[0].alarm_name
          console_login_no_mfa   = aws_cloudwatch_metric_alarm.console_login_no_mfa[0].alarm_name
          iam_policy_changes     = aws_cloudwatch_metric_alarm.iam_policy_changes[0].alarm_name
          cloudtrail_changes     = aws_cloudwatch_metric_alarm.cloudtrail_changes[0].alarm_name
        }

        metrics_namespace = "${upper(var.project_id)}/Security"
      } : null

      # Infrastructure change alarms
      infrastructure = var.enable_cloudtrail_infra_alarms ? {
        count = 3  # Number of infrastructure alarms configured

        alarms = {
          security_group_changes = aws_cloudwatch_metric_alarm.security_group_changes[0].alarm_name
          vpc_changes            = aws_cloudwatch_metric_alarm.vpc_changes[0].alarm_name
          s3_policy_changes      = aws_cloudwatch_metric_alarm.s3_policy_changes[0].alarm_name
        }

        metrics_namespace = "${upper(var.project_id)}/Infra"
      } : null
    }

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
      security_alarms_enabled        = var.enable_cloudtrail_security_alarms
      infrastructure_alarms_enabled  = var.enable_cloudtrail_infra_alarms
      slack_integration_enabled      = var.security_slack_webhook_url != null
      email_alerts_enabled           = var.security_alert_email != null
      email_handler_enabled          = var.enable_email_handler

      # Totals
      total_standards_enabled        = (
        (var.enable_aws_foundational_standard ? 1 : 0) +
        (var.enable_cis_standard ? 1 : 0) +
        (var.enable_resource_tagging_standard ? 1 : 0)
      )
      total_alarms                   = (
        (var.enable_cloudtrail_security_alarms ? 5 : 0) +
        (var.enable_cloudtrail_infra_alarms ? 3 : 0)
      )
    }
  }
}

