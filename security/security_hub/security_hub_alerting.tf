################################################################################
# SECURITY HUB ALERTING – EventBridge -> SNS/Lambda
# Purpose: Route Security Hub findings to notification channels.
# Toggle: var.enable_security_alerting
################################################################################

locals {
  alerts_rule_prefix = "${var.env}-securityhub"
  alerts_tags = {
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}


# ################################################################################
# # SNS EMAIL SUBSCRIPTION
# ################################################################################
#
# resource "aws_sns_topic_subscription" "security_email" {
#   count = var.enable_security_alerting && var.security_alert_email != null ? 1 : 0
#
#   topic_arn = aws_sns_topic.security_alerts[0].arn
#   protocol  = "email"
#   endpoint  = var.security_alert_email
# }

################################################################################
# EVENTBRIDGE – SECURITY HUB FINDINGS
################################################################################

resource "aws_cloudwatch_event_rule" "securityhub_findings" {
  count = var.enable_security_alerting ? 1 : 0

  name        = "${local.alerts_rule_prefix}-findings"
  description = "Capture all Security Hub imported findings"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = [
      "Security Hub Findings - Imported",
      "Findings Imported V2"
    ]
  })

  tags = local.alerts_tags
}

################################################################################
# EVENTBRIDGE TARGET → SNS
################################################################################

resource "aws_cloudwatch_event_target" "securityhub_findings_raw_to_sns" {
  count = var.enable_security_alerting ? 1 : 0

  rule      = aws_cloudwatch_event_rule.securityhub_findings[0].name
  target_id = "SendRawToSNS"
  arn       = var.security_alerts_sns_topic_arn
}
