
################################################################################
# SNS TOPIC POLICY – Allow EventBridge to Publish
################################################################################
resource "aws_sns_topic_policy" "combined_publish_policy" {
  arn = var.security_alerts_sns_topic_arn

  policy = jsonencode({
    Version = "2012-10-17",
    Id      = "CombinedPublishPolicy",
    Statement = [
      # EventBridge
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
      },
      # CloudWatch
      {
        Sid       = "AllowCloudWatchAlarmsToPublish",
        Effect    = "Allow",
        Principal = { Service = "cloudwatch.amazonaws.com" },
        Action    = "sns:Publish",
        Resource  = var.security_alerts_sns_topic_arn
      }
    ]
  })
}
