################################################################################
# SNS TOPIC – CENTRAL SECURITY ALERTS
################################################################################

resource "aws_sns_topic" "security_alerts" {
  name         = "${var.env}-${var.project_id}-security-alerts"
  display_name = "${upper(var.project_id)} ${upper(var.env)} Security Alerts"

  tags = {
    Name        = "${var.env}-${var.project_id}-security-alerts"
    Environment = var.env
    Project     = var.project_id
    Purpose     = "SecurityAlerting"
    ManagedBy   = "Terraform"
  }
}

################################################################################
# BASIC EMAIL SUBSCRIPTION (Optional - Simple SNS Email)
# Only created if enable_email_alerts = true AND enable_email_handler = false
################################################################################

resource "aws_sns_topic_subscription" "security_email" {
  count = var.enable_email_alerts && !var.enable_email_handler && var.security_alert_email != null ? 1 : 0

  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.security_alert_email
}

