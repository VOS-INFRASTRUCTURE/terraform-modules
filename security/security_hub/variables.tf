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
  description = "Enable AWS Security Hub (master toggle - must be true for any standards to be enabled)"
  type        = bool
  default     = true
}

variable "enable_aws_foundational_standard" {
  description = "Enable AWS Foundational Security Best Practices v1.0.0 standard"
  type        = bool
  default     = true
}

variable "enable_cis_standard" {
  description = "Enable CIS AWS Foundations Benchmark v5.0.0 standard"
  type        = bool
  default     = true
}

variable "enable_resource_tagging_standard" {
  description = "Enable AWS Resource Tagging Standard v1.0.0"
  type        = bool
  default     = false  # Optional, not required for core security
}

variable "enable_guardduty_integration" {
  description = "Enable GuardDuty product subscription in Security Hub (requires GuardDuty to be enabled)"
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
# Email Handler Configuration (Beautiful HTML Emails via SES)
################################################################################

variable "enable_email_handler" {
  description = "Enable Lambda-based email handler for beautiful HTML emails (requires SES). If false, uses basic SNS email subscription."
  type        = bool
  default     = false
}

variable "ses_from_email" {
  description = "SES verified email address to send security alerts from (required if enable_email_handler = true)"
  type        = string
  default     = null

  validation {
    condition     = var.ses_from_email == null || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.ses_from_email))
    error_message = "SES from email must be a valid email address"
  }
}

variable "ses_to_emails" {
  description = "List of email addresses to send security alerts to (required if enable_email_handler = true)"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for email in var.ses_to_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))])
    error_message = "All SES to emails must be valid email addresses"
  }
}

variable "lambda_log_level" {
  description = "Log level for Lambda functions (DEBUG, INFO, WARNING, ERROR)"
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.lambda_log_level)
    error_message = "Lambda log level must be one of: DEBUG, INFO, WARNING, ERROR"
  }
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


