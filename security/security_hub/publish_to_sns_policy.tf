
################################################################################
# SNS TOPIC POLICY – Allow EventBridge to Publish
################################################################################

resource "aws_sns_topic_policy" "security_alerts_policy" {
  count = var.enable_security_alerting ? 1 : 0

  arn = var.security_alerts_sns_topic_arn

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowEventBridgePublish",
        Effect    = "Allow",
        Principal = { Service = "events.amazonaws.com" },
        Action    = "sns:Publish",
        Resource  = var.security_alerts_sns_topic_arn,
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.securityhub_findings[0].arn
          }
        }
      }
    ]
  })
}
