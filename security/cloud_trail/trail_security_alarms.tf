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

  # Determine if alarms should be created
  # Uses only boolean flags that are known at plan time
  create_security_alarms = var.enable_alarms && var.enable_cloudtrail_security_alarms
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

  depends_on = [aws_cloudwatch_log_group.this]
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
# Root Account Usage (CIS AWS Foundations Benchmark v1.4.0 - 4.3 / Security Hub CloudWatch.1)
#
# Pattern is byte-exact per CIS 4.3 / AWS Security Hub remediation. Security
# Hub's CloudWatch.1 check fails if any field is added, removed, or altered.
################################################################################

resource "aws_cloudwatch_log_metric_filter" "root_account_usage" {
  count = local.create_security_alarms ? 1 : 0

  name           = "${var.env}-root-account-usage"
  log_group_name = local.ct_log_group_name

  pattern = <<EOF
{ $.userIdentity.type = "Root" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != "AwsServiceEvent" }
EOF

  metric_transformation {
    name      = "RootAccountUsage"
    namespace = local.security_metrics_namespace
    value     = "1"
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_cloudwatch_metric_alarm" "root_account_usage" {
  count = local.create_security_alarms ? 1 : 0

  alarm_name          = "${var.env}-root-account-usage"
  alarm_description   = "CIS 4.3 / Security Hub CloudWatch.1 – Root account activity detected"
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
# Console Login Without MFA (CIS AWS Foundations Benchmark v1.2.0 - 3.2 / Security Hub CloudWatch.3)
#
# Note: CIS v1.4.0 dropped this from its numbered 4.x control list (v1.4.0's
# own "4.6" slot is Console Authentication Failures, handled separately
# below). Security Hub still enforces CloudWatch.3 as a standalone control
# tied to the legacy CIS v1.2.0/3.2 requirement, so it's included here.
# Pattern is byte-exact per AWS Security Hub CloudWatch.3 remediation.
################################################################################

resource "aws_cloudwatch_log_metric_filter" "console_login_no_mfa" {
  count = local.create_security_alarms ? 1 : 0

  name           = "${var.env}-console-login-no-mfa"
  log_group_name = local.ct_log_group_name

  # Matches ConsoleLogin events where MFA was not used
  pattern = <<EOF
{ ($.eventName = "ConsoleLogin") && ($.additionalEventData.MFAUsed != "Yes") && ($.userIdentity.type = "IAMUser") && ($.responseElements.ConsoleLogin = "Success") }
EOF

  metric_transformation {
    name      = "ConsoleLoginNoMFA"
    namespace = local.security_metrics_namespace
    value     = "1"
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_cloudwatch_metric_alarm" "console_login_no_mfa" {
  count = local.create_security_alarms ? 1 : 0

  alarm_name          = "${var.env}-console-login-no-mfa"
  alarm_description   = "Security Hub CloudWatch.3 – Console login without MFA detected"
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
# IAM Policy Changes (CIS AWS Foundations Benchmark v1.4.0 - 4.4 / Security Hub CloudWatch.4)
#
# Pattern is byte-exact per AWS Security Hub CloudWatch.4 remediation. The
# full 16-event list is deliberately NOT scoped with an eventSource clause -
# every event name below is unique to iam.amazonaws.com, so AWS's own
# published pattern omits the eventSource filter entirely.
################################################################################

resource "aws_cloudwatch_log_metric_filter" "iam_policy_changes" {
  count = local.create_security_alarms ? 1 : 0

  name           = "${var.env}-iam-policy-changes"
  log_group_name = local.ct_log_group_name

  pattern = <<EOF
{ ($.eventName = DeleteGroupPolicy) || ($.eventName = DeleteRolePolicy) || ($.eventName = DeleteUserPolicy) || ($.eventName = PutGroupPolicy) || ($.eventName = PutRolePolicy) || ($.eventName = PutUserPolicy) || ($.eventName = CreatePolicy) || ($.eventName = DeletePolicy) || ($.eventName = CreatePolicyVersion) || ($.eventName = DeletePolicyVersion) || ($.eventName = AttachRolePolicy) || ($.eventName = DetachRolePolicy) || ($.eventName = AttachUserPolicy) || ($.eventName = DetachUserPolicy) || ($.eventName = AttachGroupPolicy) || ($.eventName = DetachGroupPolicy) }
EOF

  metric_transformation {
    name      = "IAMPolicyChanges"
    namespace = local.security_metrics_namespace
    value     = "1"
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_cloudwatch_metric_alarm" "iam_policy_changes" {
  count = local.create_security_alarms ? 1 : 0

  alarm_name          = "${var.env}-iam-policy-changes"
  alarm_description   = "CIS 4.4 / Security Hub CloudWatch.4 – IAM policy changes detected"
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
# CloudTrail Configuration Changes (CIS AWS Foundations Benchmark v1.4.0 - 4.5 / Security Hub CloudWatch.5)
#
# Pattern is byte-exact per CIS 4.5 / AWS Security Hub remediation.
################################################################################

resource "aws_cloudwatch_log_metric_filter" "cloudtrail_changes" {
  count = local.create_security_alarms ? 1 : 0

  name           = "${var.env}-cloudtrail-changes"
  log_group_name = local.ct_log_group_name

  # Detects CreateTrail, UpdateTrail, DeleteTrail, StartLogging, StopLogging
  pattern = <<EOF
{ ($.eventName = CreateTrail) || ($.eventName = UpdateTrail) || ($.eventName = DeleteTrail) || ($.eventName = StartLogging) || ($.eventName = StopLogging) }
EOF

  metric_transformation {
    name      = "CloudTrailChanges"
    namespace = local.security_metrics_namespace
    value     = "1"
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_cloudwatch_metric_alarm" "cloudtrail_changes" {
  count = local.create_security_alarms ? 1 : 0

  alarm_name          = "${var.env}-cloudtrail-changes"
  alarm_description   = "CIS 4.5 / Security Hub CloudWatch.5 – CloudTrail configuration changes detected"
  namespace           = local.security_metrics_namespace
  metric_name         = "CloudTrailChanges"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [var.security_alerts_sns_topic_arn]
}

################################################################################
# Console Authentication Failures (CIS AWS Foundations Benchmark v1.4.0 - 4.6 / Security Hub CloudWatch.6)
#
# Pattern is byte-exact per CIS 4.6 / AWS Security Hub remediation.
################################################################################

resource "aws_cloudwatch_log_metric_filter" "console_auth_failures" {
  count = local.create_security_alarms ? 1 : 0

  name           = "${var.env}-console-auth-failures"
  log_group_name = local.ct_log_group_name

  pattern = <<EOF
{ ($.eventName = ConsoleLogin) && ($.errorMessage = "Failed authentication") }
EOF

  metric_transformation {
    name      = "ConsoleAuthenticationFailures"
    namespace = local.security_metrics_namespace
    value     = "1"
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_cloudwatch_metric_alarm" "console_auth_failures" {
  count = local.create_security_alarms ? 1 : 0

  alarm_name          = "${var.env}-console-auth-failures"
  alarm_description   = "CIS 4.6 / Security Hub CloudWatch.6 – AWS Management Console authentication failures detected"
  namespace           = local.security_metrics_namespace
  metric_name         = "ConsoleAuthenticationFailures"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [var.security_alerts_sns_topic_arn]
}

################################################################################
# CMK Disabled or Scheduled for Deletion (CIS AWS Foundations Benchmark v1.4.0 - 4.7 / Security Hub CloudWatch.7)
#
# Pattern is byte-exact per CIS 4.7 / AWS Security Hub remediation.
################################################################################

resource "aws_cloudwatch_log_metric_filter" "cmk_disable_or_deletion" {
  count = local.create_security_alarms ? 1 : 0

  name           = "${var.env}-cmk-disable-or-deletion"
  log_group_name = local.ct_log_group_name

  pattern = <<EOF
{ ($.eventSource = kms.amazonaws.com) && (($.eventName = DisableKey) || ($.eventName = ScheduleKeyDeletion)) }
EOF

  metric_transformation {
    name      = "CMKDisableOrDeletion"
    namespace = local.security_metrics_namespace
    value     = "1"
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_cloudwatch_metric_alarm" "cmk_disable_or_deletion" {
  count = local.create_security_alarms ? 1 : 0

  alarm_name          = "${var.env}-cmk-disable-or-deletion"
  alarm_description   = "CIS 4.7 / Security Hub CloudWatch.7 – KMS CMK disabled or scheduled for deletion"
  namespace           = local.security_metrics_namespace
  metric_name         = "CMKDisableOrDeletion"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [var.security_alerts_sns_topic_arn]
}

################################################################################
# AWS Config Configuration Changes (CIS AWS Foundations Benchmark v1.4.0 - 4.9 / Security Hub CloudWatch.9)
#
# Pattern is byte-exact per CIS 4.9 / AWS Security Hub remediation. Grouped
# with the audit-trail-integrity alarms above (CloudTrail changes, IAM policy
# changes) since AWS Config, like CloudTrail, is part of the account's
# auditability/visibility control plane rather than network infrastructure.
################################################################################

resource "aws_cloudwatch_log_metric_filter" "aws_config_changes" {
  count = local.create_security_alarms ? 1 : 0

  name           = "${var.env}-aws-config-changes"
  log_group_name = local.ct_log_group_name

  pattern = <<EOF
{ ($.eventSource = config.amazonaws.com) && (($.eventName = StopConfigurationRecorder) || ($.eventName = DeleteDeliveryChannel) || ($.eventName = PutDeliveryChannel) || ($.eventName = PutConfigurationRecorder)) }
EOF

  metric_transformation {
    name      = "AWSConfigChanges"
    namespace = local.security_metrics_namespace
    value     = "1"
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_cloudwatch_metric_alarm" "aws_config_changes" {
  count = local.create_security_alarms ? 1 : 0

  alarm_name          = "${var.env}-aws-config-changes"
  alarm_description   = "CIS 4.9 / Security Hub CloudWatch.9 – AWS Config configuration changes detected"
  namespace           = local.security_metrics_namespace
  metric_name         = "AWSConfigChanges"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [var.security_alerts_sns_topic_arn]
}
