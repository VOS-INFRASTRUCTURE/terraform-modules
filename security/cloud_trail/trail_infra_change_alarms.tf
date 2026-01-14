################################################################################
# CLOUDTRAIL INFRASTRUCTURE CHANGE ALARMS
# Purpose: Detect changes to IAM, VPC, CloudTrail configuration impacting posture.
# Toggle: var.enable_cloudtrail_infra_alarms
# Note: SNS topic is managed by the security_notification module, not this module.
################################################################################

locals {
  infra_metrics_namespace = "${upper(var.project_id)}/Infra"

  # Determine if infrastructure alarms should be created (requires both flag and SNS topic ARN)
  create_infra_alarms = var.enable_cloudtrail_infra_alarms && var.security_alerts_sns_topic_arn != null
}

################################################################################
# 1️⃣ Security Group Changes
################################################################################

resource "aws_cloudwatch_log_metric_filter" "security_group_changes" {
  count = local.create_infra_alarms ? 1 : 0

  name           = "${var.env}-security-group-changes"
  log_group_name = local.ct_log_group_name

  pattern = <<EOF
{ ($.eventSource = "ec2.amazonaws.com") &&
  (($.eventName = "AuthorizeSecurityGroupIngress") ||
   ($.eventName = "AuthorizeSecurityGroupEgress") ||
   ($.eventName = "RevokeSecurityGroupIngress") ||
   ($.eventName = "RevokeSecurityGroupEgress") ||
   ($.eventName = "CreateSecurityGroup") ||
   ($.eventName = "DeleteSecurityGroup")) }
EOF

  metric_transformation {
    name      = "SecurityGroupChanges"
    namespace = local.infra_metrics_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "security_group_changes" {
  count = local.create_infra_alarms ? 1 : 0

  alarm_name          = "${var.env}-security-group-changes"
  alarm_description   = "CIS – Security Group changes detected"
  namespace           = local.infra_metrics_namespace
  metric_name         = "SecurityGroupChanges"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [var.security_alerts_sns_topic_arn]
}

################################################################################
# 2️⃣ VPC / Route / Gateway Changes
################################################################################

resource "aws_cloudwatch_log_metric_filter" "vpc_changes" {
  count = local.create_infra_alarms ? 1 : 0

  name           = "${var.env}-vpc-changes"
  log_group_name = local.ct_log_group_name

  pattern = <<EOF
{ ($.eventSource = "ec2.amazonaws.com") &&
  (($.eventName = "CreateVpc") ||
   ($.eventName = "DeleteVpc") ||
   ($.eventName = "CreateRoute") ||
   ($.eventName = "DeleteRoute") ||
   ($.eventName = "CreateInternetGateway") ||
   ($.eventName = "DeleteInternetGateway") ||
   ($.eventName = "CreateNatGateway") ||
   ($.eventName = "DeleteNatGateway")) }
EOF

  metric_transformation {
    name      = "VPCChanges"
    namespace = local.infra_metrics_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "vpc_changes" {
  count = local.create_infra_alarms ? 1 : 0

  alarm_name          = "${var.env}-vpc-changes"
  alarm_description   = "CIS – VPC, route, or gateway changes detected"
  namespace           = local.infra_metrics_namespace
  metric_name         = "VPCChanges"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [var.security_alerts_sns_topic_arn]
}

################################################################################
# 3️⃣ S3 Bucket Policy Changes
################################################################################

resource "aws_cloudwatch_log_metric_filter" "s3_policy_changes" {
  count = local.create_infra_alarms ? 1 : 0

  name           = "${var.env}-s3-policy-changes"
  log_group_name = local.ct_log_group_name

  pattern = <<EOF
{ ($.eventSource = "s3.amazonaws.com") &&
  (($.eventName = "PutBucketPolicy") ||
   ($.eventName = "DeleteBucketPolicy")) }
EOF

  metric_transformation {
    name      = "S3PolicyChanges"
    namespace = local.infra_metrics_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "s3_policy_changes" {
  count = local.create_infra_alarms ? 1 : 0

  alarm_name          = "${var.env}-s3-policy-changes"
  alarm_description   = "CIS – S3 bucket policy changes detected"
  namespace           = local.infra_metrics_namespace
  metric_name         = "S3PolicyChanges"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [var.security_alerts_sns_topic_arn]
}
