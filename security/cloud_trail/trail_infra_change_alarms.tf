################################################################################
# CLOUDTRAIL INFRASTRUCTURE CHANGE ALARMS
# Purpose: Detect changes to IAM, VPC, CloudTrail configuration impacting posture.
# Toggle: var.enable_cloudtrail_infra_alarms
# Note: SNS topic is managed by the security_notification module, not this module.
################################################################################

locals {
  infra_metrics_namespace = "${upper(var.project_id)}/Infra"

  # Determine if infrastructure alarms should be created
  # Uses only boolean flags that are known at plan time
  create_infra_alarms = var.enable_alarms && var.enable_cloudtrail_infra_alarms
}

################################################################################
# 1️⃣ Security Group Changes (CIS AWS Foundations Benchmark v1.4.0 - 4.10 / Security Hub CloudWatch.10)
#
# Pattern is byte-exact per CIS 4.10 / AWS Security Hub remediation.
################################################################################

resource "aws_cloudwatch_log_metric_filter" "security_group_changes" {
  count = local.create_infra_alarms ? 1 : 0

  name           = "${var.env}-security-group-changes"
  log_group_name = local.ct_log_group_name

  pattern = <<EOF
{ ($.eventName = AuthorizeSecurityGroupIngress) || ($.eventName = AuthorizeSecurityGroupEgress) || ($.eventName = RevokeSecurityGroupIngress) || ($.eventName = RevokeSecurityGroupEgress) || ($.eventName = CreateSecurityGroup) || ($.eventName = DeleteSecurityGroup) }
EOF

  metric_transformation {
    name      = "SecurityGroupChanges"
    namespace = local.infra_metrics_namespace
    value     = "1"
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_cloudwatch_metric_alarm" "security_group_changes" {
  count = local.create_infra_alarms ? 1 : 0

  alarm_name          = "${var.env}-security-group-changes"
  alarm_description   = "CIS 4.10 / Security Hub CloudWatch.10 – Security Group changes detected"
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
# 2️⃣ Network ACL Changes (CIS AWS Foundations Benchmark v1.4.0 - 4.11 / Security Hub CloudWatch.11)
#
# Pattern is byte-exact per CIS 4.11 / AWS Security Hub remediation. Split
# out of the old combined "vpc_changes" filter - CIS/Security Hub treat NACL,
# gateway, route-table, and VPC changes as 4 SEPARATE controls, each
# requiring its own dedicated metric filter and alarm.
################################################################################

resource "aws_cloudwatch_log_metric_filter" "network_acl_changes" {
  count = local.create_infra_alarms ? 1 : 0

  name           = "${var.env}-network-acl-changes"
  log_group_name = local.ct_log_group_name

  pattern = <<EOF
{ ($.eventName = CreateNetworkAcl) || ($.eventName = CreateNetworkAclEntry) || ($.eventName = DeleteNetworkAcl) || ($.eventName = DeleteNetworkAclEntry) || ($.eventName = ReplaceNetworkAclEntry) || ($.eventName = ReplaceNetworkAclAssociation) }
EOF

  metric_transformation {
    name      = "NetworkACLChanges"
    namespace = local.infra_metrics_namespace
    value     = "1"
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_cloudwatch_metric_alarm" "network_acl_changes" {
  count = local.create_infra_alarms ? 1 : 0

  alarm_name          = "${var.env}-network-acl-changes"
  alarm_description   = "CIS 4.11 / Security Hub CloudWatch.11 – Network ACL changes detected"
  namespace           = local.infra_metrics_namespace
  metric_name         = "NetworkACLChanges"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [var.security_alerts_sns_topic_arn]
}

################################################################################
# 3️⃣ Network Gateway Changes (CIS AWS Foundations Benchmark v1.4.0 - 4.12 / Security Hub CloudWatch.12)
#
# Pattern is byte-exact per CIS 4.12 / AWS Security Hub remediation. Split
# out of the old combined "vpc_changes" filter (see note above).
################################################################################

resource "aws_cloudwatch_log_metric_filter" "network_gateway_changes" {
  count = local.create_infra_alarms ? 1 : 0

  name           = "${var.env}-network-gateway-changes"
  log_group_name = local.ct_log_group_name

  pattern = <<EOF
{ ($.eventName = CreateCustomerGateway) || ($.eventName = DeleteCustomerGateway) || ($.eventName = AttachInternetGateway) || ($.eventName = CreateInternetGateway) || ($.eventName = DeleteInternetGateway) || ($.eventName = DetachInternetGateway) }
EOF

  metric_transformation {
    name      = "NetworkGatewayChanges"
    namespace = local.infra_metrics_namespace
    value     = "1"
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_cloudwatch_metric_alarm" "network_gateway_changes" {
  count = local.create_infra_alarms ? 1 : 0

  alarm_name          = "${var.env}-network-gateway-changes"
  alarm_description   = "CIS 4.12 / Security Hub CloudWatch.12 – Network gateway changes detected"
  namespace           = local.infra_metrics_namespace
  metric_name         = "NetworkGatewayChanges"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [var.security_alerts_sns_topic_arn]
}

################################################################################
# 4️⃣ Route Table Changes (CIS AWS Foundations Benchmark v1.4.0 - 4.13 / Security Hub CloudWatch.13)
#
# Pattern is byte-exact per CIS 4.13 / AWS Security Hub remediation. Split
# out of the old combined "vpc_changes" filter (see note above).
################################################################################

resource "aws_cloudwatch_log_metric_filter" "route_table_changes" {
  count = local.create_infra_alarms ? 1 : 0

  name           = "${var.env}-route-table-changes"
  log_group_name = local.ct_log_group_name

  pattern = <<EOF
{ ($.eventName = CreateRoute) || ($.eventName = CreateRouteTable) || ($.eventName = ReplaceRoute) || ($.eventName = ReplaceRouteTableAssociation) || ($.eventName = DeleteRouteTable) || ($.eventName = DeleteRoute) || ($.eventName = DisassociateRouteTable) }
EOF

  metric_transformation {
    name      = "RouteTableChanges"
    namespace = local.infra_metrics_namespace
    value     = "1"
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_cloudwatch_metric_alarm" "route_table_changes" {
  count = local.create_infra_alarms ? 1 : 0

  alarm_name          = "${var.env}-route-table-changes"
  alarm_description   = "CIS 4.13 / Security Hub CloudWatch.13 – Route table changes detected"
  namespace           = local.infra_metrics_namespace
  metric_name         = "RouteTableChanges"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [var.security_alerts_sns_topic_arn]
}

################################################################################
# 5️⃣ VPC Changes (CIS AWS Foundations Benchmark v1.4.0 - 4.14 / Security Hub CloudWatch.14)
#
# Pattern is byte-exact per CIS 4.14 / AWS Security Hub remediation. Now
# scoped to VPC-specific events only - route/gateway events (previously
# mixed in here) live in their own dedicated filters above.
################################################################################

resource "aws_cloudwatch_log_metric_filter" "vpc_changes" {
  count = local.create_infra_alarms ? 1 : 0

  name           = "${var.env}-vpc-changes"
  log_group_name = local.ct_log_group_name

  pattern = <<EOF
{ ($.eventName = CreateVpc) || ($.eventName = DeleteVpc) || ($.eventName = ModifyVpcAttribute) || ($.eventName = AcceptVpcPeeringConnection) || ($.eventName = CreateVpcPeeringConnection) || ($.eventName = DeleteVpcPeeringConnection) || ($.eventName = RejectVpcPeeringConnection) || ($.eventName = AttachClassicLinkVpc) || ($.eventName = DetachClassicLinkVpc) || ($.eventName = DisableVpcClassicLink) || ($.eventName = EnableVpcClassicLink) }
EOF

  metric_transformation {
    name      = "VPCChanges"
    namespace = local.infra_metrics_namespace
    value     = "1"
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_cloudwatch_metric_alarm" "vpc_changes" {
  count = local.create_infra_alarms ? 1 : 0

  alarm_name          = "${var.env}-vpc-changes"
  alarm_description   = "CIS 4.14 / Security Hub CloudWatch.14 – VPC changes detected"
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
# 6️⃣ S3 Bucket Policy Changes (CIS AWS Foundations Benchmark v1.4.0 - 4.8 / Security Hub CloudWatch.8)
#
# Pattern is byte-exact per CIS 4.8 / AWS Security Hub remediation.
################################################################################

resource "aws_cloudwatch_log_metric_filter" "s3_policy_changes" {
  count = local.create_infra_alarms ? 1 : 0

  name           = "${var.env}-s3-policy-changes"
  log_group_name = local.ct_log_group_name

  pattern = <<EOF
{ ($.eventSource = s3.amazonaws.com) && (($.eventName = PutBucketAcl) || ($.eventName = PutBucketPolicy) || ($.eventName = PutBucketCors) || ($.eventName = PutBucketLifecycle) || ($.eventName = PutBucketReplication) || ($.eventName = DeleteBucketPolicy) || ($.eventName = DeleteBucketCors) || ($.eventName = DeleteBucketLifecycle) || ($.eventName = DeleteBucketReplication)) }
EOF

  metric_transformation {
    name      = "S3PolicyChanges"
    namespace = local.infra_metrics_namespace
    value     = "1"
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_cloudwatch_metric_alarm" "s3_policy_changes" {
  count = local.create_infra_alarms ? 1 : 0

  alarm_name          = "${var.env}-s3-policy-changes"
  alarm_description   = "CIS 4.8 / Security Hub CloudWatch.8 – S3 bucket policy changes detected"
  namespace           = local.infra_metrics_namespace
  metric_name         = "S3PolicyChanges"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [var.security_alerts_sns_topic_arn]
}
