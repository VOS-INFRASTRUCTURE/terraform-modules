# ============================================================================
# CloudTrail Module Variables
#
# Purpose: Centralize inputs for reusable CloudTrail logging setup.
# Notes: Variable names are stable to avoid breaking callers; only comments/grouping
#        are improved for clarity. Defaults chosen for safe operation.
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

variable "enable_bucket_versioning" {
  description = "Enable S3 bucket versioning for CloudTrail logs (provides additional protection against accidental deletions and tampering)"
  type        = bool
  default     = true
}

################################################################################
# SNS Alerting Configuration
################################################################################

variable "security_alerts_sns_topic_arn" {
  description = "SNS topic ARN for CloudTrail security and infrastructure alarms (from security_notification module). Required if alarms are enabled."
  type        = string
  default     = null

  validation {
    condition     = var.security_alerts_sns_topic_arn == null || can(regex("^arn:aws:sns:[a-z0-9-]+:[0-9]{12}:.+$", var.security_alerts_sns_topic_arn))
    error_message = "Must be a valid SNS topic ARN (e.g., arn:aws:sns:us-east-1:123456789012:my-topic) or null"
  }
}

################################################################################
# CloudTrail Infrastructure Change Alarms
################################################################################

variable "enable_cloudtrail_infra_alarms" {
  description = "Enable infrastructure change detection alarms (security groups, VPC changes, S3 bucket policy changes). Requires security_alerts_sns_topic_arn to be set."
  type        = bool
  default     = true
}

################################################################################
# CloudTrail Security Alarms (CIS Benchmark)
################################################################################

variable "enable_cloudtrail_security_alarms" {
  description = "Enable CloudTrail security metric filters and alarms for CIS benchmark compliance (unauthorized API calls, root usage, MFA, IAM changes, CloudTrail changes). Requires security_alerts_sns_topic_arn to be set."
  type        = bool
  default     = true
}

