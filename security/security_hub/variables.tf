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
  description = "SNS topic ARN for security alerts (from security_notification module). Used as destination for EventBridge targets."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:sns:[a-z0-9-]+:[0-9]{12}:.+$", var.security_alerts_sns_topic_arn))
    error_message = "Must be a valid SNS topic ARN (e.g., arn:aws:sns:us-east-1:123456789012:my-topic)"
  }
}

