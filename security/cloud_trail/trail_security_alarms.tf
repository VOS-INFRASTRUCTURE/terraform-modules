################################################################################
# CLOUDTRAIL SECURITY ALARMS (CIS / AWS Foundations)
#
# Purpose:
# - Detect high-risk activities via CloudTrail logs (e.g., unauthorized API calls,
#   root usage, IAM policy changes, CloudTrail config changes).
# - Emit metrics to a project-scoped namespace and alarm via external SNS topic.
#
# Toggle:
# - Controlled by var.enable_cloudtrail_security_alarms (bool).
# - Requires var.security_alerts_sns_topic_arn to be provided.
#
# Note: SNS topic is managed by the security_notification module, not this module.
################################################################################

# ----------------------------
# Shared locals for consistency
# ----------------------------
locals {
  security_metrics_namespace = "${upper(var.project_id)}/Security"

  # Determine if alarms should be created (requires both flag and SNS topic ARN)
  create_security_alarms = var.enable_cloudtrail_security_alarms && var.security_alerts_sns_topic_arn != null
}

################################################################################
# Unauthorized API Calls (CIS 3.1)
################################################################################

resource "aws_cloudwatch_log_metric_filter" "unauthorized_api_calls" {
  count = local.create_security_alarms ? 1 : 0

  name           = "${var.env}-unauthorized-api-calls"
  log_group_name = local.ct_log_group_name

  # Matches AccessDenied or UnauthorizedOperation errors anywhere in events
  pattern = <<EOF
{ ($.errorCode = "*UnauthorizedOperation") || ($.errorCode = "AccessDenied*") }
EOF

  metric_transformation {
    name      = "UnauthorizedAPICalls"
    namespace = local.security_metrics_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "unauthorized_api_calls" {
  count = local.create_security_alarms ? 1 : 0

  alarm_name          = "${var.env}-unauthorized-api-calls"
  alarm_description   = "CIS 3.1 – Unauthorized AWS API calls detected"
  namespace           = local.security_metrics_namespace
  metric_name         = "UnauthorizedAPICalls"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [var.security_alerts_sns_topic_arn]
}

################################################################################
# Root Account Usage (CIS 1.1)
################################################################################

resource "aws_cloudwatch_log_metric_filter" "root_account_usage" {
  count = local.create_security_alarms ? 1 : 0

  name           = "${var.env}-root-account-usage"
  log_group_name = local.ct_log_group_name

  pattern = <<EOF
{ $.userIdentity.type = "Root" && $.userIdentity.invokedBy NOT EXISTS }
EOF

  metric_transformation {
    name      = "RootAccountUsage"
    namespace = local.security_metrics_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "root_account_usage" {
  count = local.create_security_alarms ? 1 : 0

  alarm_name          = "${var.env}-root-account-usage"
  alarm_description   = "CIS 1.1 – Root account activity detected"
  namespace           = local.security_metrics_namespace
  metric_name         = "RootAccountUsage"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [var.security_alerts_sns_topic_arn]
}

################################################################################
# Console Login Without MFA (CIS 1.2)
################################################################################

resource "aws_cloudwatch_log_metric_filter" "console_login_no_mfa" {
  count = local.create_security_alarms ? 1 : 0

  name           = "${var.env}-console-login-no-mfa"
  log_group_name = local.ct_log_group_name

  # Matches ConsoleLogin events where MFA was not used
  pattern = <<EOF
{ $.eventName = "ConsoleLogin" && $.additionalEventData.MFAUsed != "Yes" }
EOF

  metric_transformation {
    name      = "ConsoleLoginNoMFA"
    namespace = local.security_metrics_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "console_login_no_mfa" {
  count = local.create_security_alarms ? 1 : 0

  alarm_name          = "${var.env}-console-login-no-mfa"
  alarm_description   = "CIS 1.2 – Console login without MFA detected"
  namespace           = local.security_metrics_namespace
  metric_name         = "ConsoleLoginNoMFA"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [var.security_alerts_sns_topic_arn]
}

################################################################################
# IAM Policy Changes (CIS 3.7)
################################################################################

resource "aws_cloudwatch_log_metric_filter" "iam_policy_changes" {
  count = local.create_security_alarms ? 1 : 0

  name           = "${var.env}-iam-policy-changes"
  log_group_name = local.ct_log_group_name

  # Detect policy attachment/creation/deletion on users and roles
  pattern = <<EOF
{ ($.eventSource = "iam.amazonaws.com") &&
  (($.eventName = "PutUserPolicy") ||
   ($.eventName = "AttachUserPolicy") ||
   ($.eventName = "PutRolePolicy") ||
   ($.eventName = "AttachRolePolicy") ||
   ($.eventName = "CreatePolicy") ||
   ($.eventName = "DeletePolicy")) }
EOF

  metric_transformation {
    name      = "IAMPolicyChanges"
    namespace = local.security_metrics_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "iam_policy_changes" {
  count = local.create_security_alarms ? 1 : 0

  alarm_name          = "${var.env}-iam-policy-changes"
  alarm_description   = "CIS 3.7 – IAM policy changes detected"
  namespace           = local.security_metrics_namespace
  metric_name         = "IAMPolicyChanges"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [var.security_alerts_sns_topic_arn]
}

################################################################################
# CloudTrail Disabled or Modified (CIS 3.4)
################################################################################

resource "aws_cloudwatch_log_metric_filter" "cloudtrail_changes" {
  count = local.create_security_alarms ? 1 : 0

  name           = "${var.env}-cloudtrail-changes"
  log_group_name = local.ct_log_group_name

  # Detects StopLogging, DeleteTrail, or UpdateTrail operations
  pattern = <<EOF
{ ($.eventSource = "cloudtrail.amazonaws.com") &&
  (($.eventName = "StopLogging") ||
   ($.eventName = "DeleteTrail") ||
   ($.eventName = "UpdateTrail")) }
EOF

  metric_transformation {
    name      = "CloudTrailChanges"
    namespace = local.security_metrics_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "cloudtrail_changes" {
  count = local.create_security_alarms ? 1 : 0

  alarm_name          = "${var.env}-cloudtrail-changes"
  alarm_description   = "CIS 3.4 – CloudTrail configuration changes detected"
  namespace           = local.security_metrics_namespace
  metric_name         = "CloudTrailChanges"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [var.security_alerts_sns_topic_arn]
}
