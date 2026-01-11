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

