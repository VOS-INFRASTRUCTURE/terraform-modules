# ============================================================================
# CloudTrail Module Variables – CERPAC
#
# Purpose: Centralize inputs for reusable CloudTrail + logging + alerting setup.
# Notes: Variable names are stable to avoid breaking callers; only comments/grouping
#        are improved for clarity. Defaults chosen for safe operation.
#
# NOTE: See section headers for toggles: enable_cloudtrail_security_alarms, enable_cloudtrail_infra_alarms, enable_security_alerting, enable_security_hub, enable_guardduty, enable_aws_config.
# ============================================================================

# ----------------------------
# Core identification & environment
# ----------------------------
variable "project_id" {
  description = "Short identifier for the project (used in naming)"
  type        = string
}

variable "env" {
  description = "Environment name (e.g., production, staging)"
  type        = string
}

# ----------------------------
# Retention & lifecycle controls
# ----------------------------
variable "retention_days" {
  description = "Retention days for CloudTrail logs in S3 and CloudWatch"
  type        = number
  default     = 90
}

variable "force_destroy" {
  description = "Allow Terraform to destroy S3 bucket with contents (use with caution)"
  type        = bool
  default     = false
}

# ----------------------------
# Security Alarms (CloudTrail event-based)
# ----------------------------
variable "enable_cloudtrail_security_alarms" {
  description = "Enable CloudTrail security metric filters and alarms (e.g., root usage, policy changes)"
  type        = bool
  default     = false
}

# ----------------------------
# Infrastructure Change Alarms (CloudTrail)
# ----------------------------
variable "enable_cloudtrail_infra_alarms" {
  description = "Enable infrastructure change detection alarms (e.g., IAM, VPC, CloudTrail config)"
  type        = bool
  default     = false
}

# ----------------------------
# EventBridge + SNS Alerting (Security Hub, GuardDuty)
# ----------------------------
variable "enable_security_alerting" {
  description = "Enable security alerting via EventBridge and SNS (routes findings to notification channels)"
  type        = bool
  default     = false
}

variable "security_alerts_sns_topic_arn" {
  description = "SNS topic ARN used for security alerts (destination for EventBridge targets)"
  type        = string
}

variable "security_alert_email" {
  description = "Email address to receive security alerts (optional, used if SNS email subscriptions are configured)"
  type        = string
  default     = null
}

variable "security_slack_webhook_url" {
  description = "Slack webhook URL (used by Lambda forwarder, optional)"
  type        = string
  default     = null
  sensitive   = true
}

# ----------------------------
# Security Hub – Standards & Findings
# ----------------------------
variable "enable_security_hub" {
  description = "Enable AWS Security Hub and subscribe to recommended standards"
  type        = bool
  default     = false
}

# ----------------------------
# GuardDuty – Threat detection options
# ----------------------------
variable "enable_guardduty" {
  description = "Enable Amazon GuardDuty threat detection"
  type        = bool
  default     = false
}

variable "enable_guardduty_s3_data_events" {
  description = "Enable GuardDuty S3 data events / malware protection"
  type        = bool
  default     = true
}

variable "enable_guardduty_eks_audit_logs" {
  description = "Enable GuardDuty EKS audit logs (only if EKS is used)"
  type        = bool
  default     = false
}

# ----------------------------
# AWS Config – Resource configuration recording (optional)
# ----------------------------
variable "enable_aws_config" {
  description = "Enable AWS Config recorder, delivery channel, and S3 bucket"
  type        = bool
  default     = false
}
