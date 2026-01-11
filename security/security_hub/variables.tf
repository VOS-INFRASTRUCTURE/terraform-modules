################################################################################
# Security Hub Module Variables
################################################################################

################################################################################
# General Configuration
################################################################################

variable "project_id" {
  description = "Project identifier used in resource naming"
  type        = string

  validation {
    condition     = length(var.project_id) > 0 && length(var.project_id) <= 50
    error_message = "Project ID must be between 1 and 50 characters"
  }
}

variable "env" {
  description = "Environment name (e.g., production, staging, development)"
  type        = string

  validation {
    condition     = can(regex("^(production|staging|development|prod|stage|dev)$", var.env))
    error_message = "Environment must be one of: production, staging, development, prod, stage, dev"
  }
}

################################################################################
# Security Hub Configuration
################################################################################

variable "enable_security_hub" {
  description = "Enable AWS Security Hub and subscribe to recommended standards (AWS Foundational, CIS, Resource Tagging)"
  type        = bool
  default     = true
}

################################################################################
# Security Alerting Configuration
################################################################################

variable "enable_security_alerting" {
  description = "Enable security alerting via EventBridge and SNS (routes Security Hub findings to notification channels)"
  type        = bool
  default     = true
}

variable "security_alerts_sns_topic_arn" {
  description = "SNS topic ARN for security alerts (used as destination for CloudWatch alarms and EventBridge targets)"
  type        = string
}

variable "security_alert_email" {
  description = "Email address to receive security alerts (optional). If provided, an SNS email subscription will be created."
  type        = string
  default     = null

  validation {
    condition     = var.security_alert_email == null || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.security_alert_email))
    error_message = "Security alert email must be a valid email address"
  }
}

variable "security_slack_webhook_url" {
  description = "Slack webhook URL for security alerts (optional). If provided, Lambda will forward HIGH/CRITICAL findings to Slack."
  type        = string
  default     = null
  sensitive   = true
}

################################################################################
# CloudTrail Security Alarms (CIS Benchmark)
################################################################################

variable "enable_cloudtrail_security_alarms" {
  description = "Enable CloudTrail security metric filters and alarms for CIS benchmark compliance (unauthorized API calls, root usage, MFA, IAM changes, CloudTrail changes)"
  type        = bool
  default     = true
}

################################################################################
# CloudTrail Infrastructure Change Alarms
################################################################################

variable "enable_cloudtrail_infra_alarms" {
  description = "Enable infrastructure change detection alarms (security groups, VPC changes, S3 bucket policy changes)"
  type        = bool
  default     = true
}


