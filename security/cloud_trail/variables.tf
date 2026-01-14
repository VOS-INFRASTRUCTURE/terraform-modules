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

variable "security_alerts_sns_topic_arn" {
  description = "SNS topic ARN for security alerts (used as destination for CloudWatch alarms and EventBridge targets)"
  type        = string
}

################################################################################
# CloudTrail Infrastructure Change Alarms
################################################################################

variable "enable_cloudtrail_infra_alarms" {
  description = "Enable infrastructure change detection alarms (security groups, VPC changes, S3 bucket policy changes)"
  type        = bool
  default     = true
}

################################################################################
# CloudTrail Security Alarms (CIS Benchmark)
################################################################################

variable "enable_cloudtrail_security_alarms" {
  description = "Enable CloudTrail security metric filters and alarms for CIS benchmark compliance (unauthorized API calls, root usage, MFA, IAM changes, CloudTrail changes)"
  type        = bool
  default     = true
}

