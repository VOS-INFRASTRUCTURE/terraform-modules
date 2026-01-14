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
# Security Alerting Configuration
################################################################################

variable "enable_email_alerts" {
  description = "Enable email notifications for security alerts. If true, either basic SNS email or SES-based email handler will be used."
  type        = bool
  default     = false
}

variable "security_alert_email" {
  description = "Email address to receive security alerts (optional). Used for basic SNS email subscription when enable_email_handler = false."
  type        = string
  default     = null

  validation {
    condition     = var.security_alert_email == null || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.security_alert_email))
    error_message = "Security alert email must be a valid email address"
  }
}

variable "enable_slack_alerts" {
  description = "Enable Slack notifications for security alerts (HIGH/CRITICAL only). Requires security_slack_webhook_url to be set."
  type        = bool
  default     = false
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

