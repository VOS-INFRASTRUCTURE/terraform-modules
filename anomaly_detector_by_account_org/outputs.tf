output "sns_topic_arn" {
  description = "ARN of the SNS topic for anomaly alerts"
  value       = aws_sns_topic.cost_anomaly_alerts.arn
}
