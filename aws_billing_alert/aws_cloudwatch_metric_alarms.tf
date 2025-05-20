# Create multiple CloudWatch Billing Alarms based on provided thresholds
resource "aws_cloudwatch_metric_alarm" "billing_alarms" {

  # Loop through each threshold value e.g. 50, 100, 200
  for_each = { for threshold in var.thresholds : threshold => threshold }

  # Alarm name will dynamically reflect the threshold value
  alarm_name = "billing-over-${each.key}-usd"

  # Trigger alarm if billing value is greater than or equal to threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"

  # Number of consecutive periods needed to trigger the alarm
  # 1 means trigger immediately after the first period breaches the threshold
  evaluation_periods = 1

  # Metric to monitor - AWS Estimated Charges
  metric_name = "EstimatedCharges"

  # Billing metrics only exist in AWS/Billing namespace
  namespace = "AWS/Billing"

  # Period is in seconds - here it's 21600 seconds = 6 hours
  # Billing data updates approx every 4-6 hours, so this is ideal
  period = 21600  # 6 hours

  # Take the maximum value seen in the period (because billing is cumulative)
  statistic = "Maximum"

  # Threshold value to trigger the alarm (dynamic per loop iteration)
  threshold = each.key

  # Enable the alarm actions to actually send notifications
  actions_enabled = true

  # Helpful description for visibility in the AWS Console
  alarm_description = "Triggered when AWS billing exceeds ${each.key} USD"

  # Notification action - send to SNS topic
  alarm_actions = [
    aws_sns_topic.billing_alerts.arn
  ]

  # Dimension to specify currency type
  # Only USD metrics are monitored here
  dimensions = {
    Currency = "USD"
  }
}
