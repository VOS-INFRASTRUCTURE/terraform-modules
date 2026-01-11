################################################################################
# AWS Config Module Variables
################################################################################

################################################################################
# General Configuration
################################################################################

variable "enable_aws_config" {
  description = "Enable or disable AWS Config. Set to false to disable all Config resources."
  type        = bool
  default     = true
}

variable "env" {
  description = "Environment name (e.g., production, staging, development)"
  type        = string

  validation {
    condition     = can(regex("^(production|staging|development|prod|stage|dev)$", var.env))
    error_message = "Environment must be one of: production, staging, development, prod, stage, dev"
  }
}

variable "project_id" {
  description = "Project identifier used in resource naming"
  type        = string

  validation {
    condition     = length(var.project_id) > 0 && length(var.project_id) <= 50
    error_message = "Project ID must be between 1 and 50 characters"
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

################################################################################
# S3 Bucket Configuration
################################################################################

variable "force_destroy_bucket" {
  description = "Allow destruction of S3 bucket even if it contains objects (DANGEROUS - use only in dev/test)"
  type        = bool
  default     = false
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on the S3 bucket to protect against accidental deletion"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of KMS key for S3 bucket encryption. If null, uses AWS-managed AES256 encryption."
  type        = string
  default     = null
}

variable "s3_key_prefix" {
  description = "Prefix for AWS Config files in S3 bucket (e.g., 'config/' or 'AWSLogs/')"
  type        = string
  default     = ""
}

################################################################################
# S3 Lifecycle Policy
################################################################################

variable "enable_lifecycle_policy" {
  description = "Enable S3 lifecycle policy to transition old logs to Glacier and expire them"
  type        = bool
  default     = true
}

variable "glacier_transition_days" {
  description = "Number of days after which to transition logs to Glacier storage class"
  type        = number
  default     = 90

  validation {
    condition     = var.glacier_transition_days >= 30
    error_message = "Glacier transition must be at least 30 days (S3 requirement)"
  }
}

variable "log_expiration_days" {
  description = "Number of days after which to permanently delete logs (0 = never expire)"
  type        = number
  default     = 2555 # ~7 years (compliance requirement)

  validation {
    condition     = var.log_expiration_days == 0 || var.log_expiration_days >= 365
    error_message = "Log expiration must be 0 (never) or at least 365 days for compliance"
  }
}

################################################################################
# Configuration Recorder Settings
################################################################################

variable "record_all_resources" {
  description = "Record all supported resource types. If false, specify resource_types."
  type        = bool
  default     = true
}

variable "include_global_resources" {
  description = "Include global resources (IAM, etc.). Enable in ONE region only to avoid duplicates."
  type        = bool
  default     = true
}

variable "resource_types" {
  description = "List of specific resource types to record (only used if record_all_resources = false)"
  type        = list(string)
  default     = []

  # Example resource types:
  # - "AWS::EC2::Instance"
  # - "AWS::EC2::SecurityGroup"
  # - "AWS::S3::Bucket"
  # - "AWS::RDS::DBInstance"
  # - "AWS::IAM::User"
  # - "AWS::IAM::Role"
  # Full list: https://docs.aws.amazon.com/config/latest/developerguide/resource-config-reference.html
}

variable "config_role_arn" {
  description = "IAM role ARN for AWS Config. If null, uses the AWS service-linked role."
  type        = string
  default     = null

  # Default: arn:aws:iam::ACCOUNT_ID:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig
  # The service-linked role is created automatically when AWS Config is first enabled
}

################################################################################
# Delivery Channel Settings
################################################################################

variable "snapshot_delivery_frequency" {
  description = <<-EOT
    Frequency for AWS Config to deliver configuration snapshots to S3.

    AWS Default: TwentyFour_Hours (if not specified)

    Options:
    - One_Hour: Most frequent, higher cost (~$2/month extra)
    - Three_Hours: Frequent monitoring
    - Six_Hours: Balanced
    - Twelve_Hours: Less frequent
    - TwentyFour_Hours: AWS default, most cost-effective

    Note: More frequent snapshots increase S3 storage costs and API calls.
    For most use cases, TwentyFour_Hours is sufficient.
  EOT
  type        = string
  default     = "TwentyFour_Hours"

  validation {
    condition = contains([
      "One_Hour",
      "Three_Hours",
      "Six_Hours",
      "Twelve_Hours",
      "TwentyFour_Hours"
    ], var.snapshot_delivery_frequency)
    error_message = "Snapshot delivery frequency must be one of: One_Hour, Three_Hours, Six_Hours, Twelve_Hours, TwentyFour_Hours"
  }
}

variable "sns_topic_arn" {
  description = "ARN of SNS topic for AWS Config notifications (optional). If null, no notifications are sent."
  type        = string
  default     = null
}

