resource "aws_sns_topic" "billing_alerts" {
  name = "billing-alert-topic"
}

resource "aws_sns_topic_subscription" "email_subscriptions" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.billing_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

