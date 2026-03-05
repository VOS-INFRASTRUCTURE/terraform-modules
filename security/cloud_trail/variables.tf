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

variable "enable_alarms" {
  description = "Master toggle to enable/disable CloudTrail alarms. Set to false if you don't want any alarms created, regardless of security_alerts_sns_topic_arn value."
  type        = bool
  default     = true
}

variable "security_alerts_sns_topic_arn" {
  description = "SNS topic ARN for CloudTrail security and infrastructure alarms (from security_notification module). Required if enable_alarms is true."
  type        = string
  default     = ""

  validation {
    condition     = var.security_alerts_sns_topic_arn == "" || can(regex("^arn:aws:sns:[a-z0-9-]+:[0-9]{12}:.+$", var.security_alerts_sns_topic_arn))
    error_message = "Must be a valid SNS topic ARN (e.g., arn:aws:sns:us-east-1:123456789012:my-topic) or empty string"
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

################################################################################
# Central / Cross-Account S3 Bucket (optional)
#
# When your organisation uses a dedicated logging/security account that owns a
# central S3 bucket for CloudTrail logs, provide its name here.
#
# Behaviour:
# - central_s3_bucket_name != null  →  use the central bucket; skip creating a
#   local bucket entirely (all bucket.tf resources are disabled).
# - central_s3_bucket_name == null  →  create and manage a local bucket as
#   usual (default behaviour).
#
# Pre-requisites when using a central bucket:
# 1. The central bucket's bucket policy must already permit CloudTrail from
#    THIS account to call s3:GetBucketAcl and s3:PutObject under the
#    AWSLogs/<this-account-id>/* prefix.
# 2. If the central bucket uses a KMS CMK, the KMS key policy must grant
#    GenerateDataKey / Decrypt rights to cloudtrail.amazonaws.com.
#
# central_s3_bucket_account_id is informational only – it is exposed in
# outputs for reference and is not used to create any cross-account resources.
################################################################################

variable "central_s3_bucket_name" {
  description = <<-EOT
    Name of an existing (central / cross-account) S3 bucket to use for
    CloudTrail logs.  When set, no local S3 bucket is created by this module.
    The bucket must already have the correct bucket policy to allow the
    CloudTrail service from this account to write logs.
    Leave as null (default) to let the module create and manage a local bucket.
  EOT
  type    = string
  default = null
}

variable "central_s3_bucket_account_id" {
  description = <<-EOT
    AWS account ID that owns the central S3 bucket (informational only).
    Used only in outputs and documentation; not required for functionality.
    Leave as null when using a locally-managed bucket.
  EOT
  type    = string
  default = null
}

