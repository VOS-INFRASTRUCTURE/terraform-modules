################################################################################
# CloudTrail Module Outputs
#
# All outputs are consolidated into a single 'cloudtrail' object for easier
# consumption and cleaner code organization.
#
# Usage:
#   module.cloudtrail.cloudtrail.bucket.name
#   module.cloudtrail.cloudtrail.trail.is_multi_region
#   module.cloudtrail.cloudtrail.log_group.retention_days
################################################################################

output "cloudtrail" {
  description = "CloudTrail resources and configuration details"
  value = {
    # ──────────────────────────────────────────────────────────────────────
    # S3 Bucket - Long-term audit log storage
    # ──────────────────────────────────────────────────────────────────────
    bucket = {
      name       = aws_s3_bucket.cloudtrail_logs.bucket      # S3 bucket name
      arn        = aws_s3_bucket.cloudtrail_logs.arn         # S3 bucket ARN
      id         = aws_s3_bucket.cloudtrail_logs.id          # S3 bucket ID
      versioning = "Enabled"                                  # Versioning status
      encryption = "AES256"                                   # Encryption type
    }

    # ──────────────────────────────────────────────────────────────────────
    # CloudWatch Log Group - Real-time log streaming
    # ──────────────────────────────────────────────────────────────────────
    log_group = {
      name           = aws_cloudwatch_log_group.this.name    # Log group name
      arn            = aws_cloudwatch_log_group.this.arn     # Log group ARN
      retention_days = var.retention_days                    # Retention period
    }

    # ──────────────────────────────────────────────────────────────────────
    # CloudTrail - Multi-region audit trail
    # ──────────────────────────────────────────────────────────────────────
    trail = {
      name              = aws_cloudtrail.trail.name          # Trail name
      arn               = aws_cloudtrail.trail.arn           # Trail ARN
      id                = aws_cloudtrail.trail.id            # Trail ID
      is_multi_region   = true                               # Multi-region enabled
      log_validation    = true                               # Log file validation enabled
      global_events     = true                               # Global service events included
      home_region       = aws_cloudtrail.trail.home_region   # Home region
    }

    # ──────────────────────────────────────────────────────────────────────
    # CloudTrail Security Alarms - CIS benchmark compliance
    # ──────────────────────────────────────────────────────────────────────
    alarms = {
      # SNS topic used for alarms (external, from security_notification module)
      sns_topic_arn = var.security_alerts_sns_topic_arn != "" ? var.security_alerts_sns_topic_arn : null

      security = var.enable_alarms && var.enable_cloudtrail_security_alarms ? {
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
      infrastructure = var.enable_alarms && var.enable_cloudtrail_infra_alarms ? {
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
    # IAM Role - CloudTrail to CloudWatch Logs
    # ──────────────────────────────────────────────────────────────────────
    iam_role = {
      name = aws_iam_role.cloudtrail_cloudwatch.name        # IAM role name
      arn  = aws_iam_role.cloudtrail_cloudwatch.arn         # IAM role ARN
    }

    # ──────────────────────────────────────────────────────────────────────
    # Configuration Summary - Quick reference for module status
    # ──────────────────────────────────────────────────────────────────────
    summary = {
      module_enabled     = true                              # Module is active
      dual_delivery      = true                              # Both S3 and CloudWatch

      # Alerting configuration
      security_alarms_enabled        = var.enable_cloudtrail_security_alarms
      infrastructure_alarms_enabled  = var.enable_cloudtrail_infra_alarms

      retention_days     = var.retention_days                # Log retention period
      force_destroy      = var.force_destroy                 # Bucket force destroy setting

      total_alarms                   = (
      (var.enable_cloudtrail_security_alarms ? 5 : 0) +
      (var.enable_cloudtrail_infra_alarms ? 3 : 0)
      )
    }
  }
}
