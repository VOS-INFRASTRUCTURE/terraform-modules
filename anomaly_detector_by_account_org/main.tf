# SNS Topic for anomaly alerts
resource "aws_sns_topic" "cost_anomaly_alerts" {
  name = "cost-anomaly-alerts"
}

# SNS Subscription to send alerts to email
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.cost_anomaly_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Create a custom anomaly monitor for each linked account
resource "aws_ce_anomaly_monitor" "linked_account_monitors" {
  for_each = { for account in var.linked_accounts : account.id => account }

  name         = "linked-account-${each.value.name}"
  monitor_type = "CUSTOM"

  monitor_specification = jsonencode({
    Dimensions = {
      Key    = "LINKED_ACCOUNT"
      Values = [each.key]
    }
  })
}

# Anomaly subscription to notify when threshold is breached
resource "aws_ce_anomaly_subscription" "anomaly_subscription" {
  name             = "linked-accounts-anomaly-subscription"
  frequency        = "IMMEDIATE"
  monitor_arn_list = [for monitor in aws_ce_anomaly_monitor.linked_account_monitors : monitor.arn]

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.cost_anomaly_alerts.arn
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_PERCENTAGE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [var.threshold_percentage]
    }
  }
}
