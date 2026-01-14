
################################################################################
# SNS TOPIC POLICY – Allow CloudWatch Alarms to Publish
################################################################################

resource "aws_sns_topic_policy" "cloudwatch_alarms_publish" {
  count = var.enable_alarms && (var.enable_cloudtrail_security_alarms || var.enable_cloudtrail_infra_alarms) ? 1 : 0

  arn = var.security_alerts_sns_topic_arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "CloudWatchAlarmsPublishPolicy"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = var.security_alerts_sns_topic_arn
      }
    ]
  })
}
