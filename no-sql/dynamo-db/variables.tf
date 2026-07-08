################################################################################
# Naming
################################################################################

variable "env" {
  description = "Environment for tagging and naming (e.g., staging, production)"
  type        = string
}

variable "project_id" {
  description = "Project ID where all project resources exist"
  type        = string
}

variable "base_name" {
  description = "Base name for the table (e.g., 'sessions', 'events')"
  type        = string
}

variable "table_name" {
  description = "Full table name override. Leave empty to derive as '<project_id>-<env>-<base_name>'"
  type        = string
  default     = ""
}

################################################################################
# Capacity
################################################################################

variable "billing_mode" {
  description = "PAY_PER_REQUEST (on-demand, recommended starting point) or PROVISIONED"
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "billing_mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "read_capacity" {
  description = "Base table read capacity units. Only used when billing_mode = PROVISIONED. Acts as the initial value if enable_autoscaling = true."
  type        = number
  default     = 5
}

variable "write_capacity" {
  description = "Base table write capacity units. Only used when billing_mode = PROVISIONED. Acts as the initial value if enable_autoscaling = true."
  type        = number
  default     = 5
}

variable "table_class" {
  description = "STANDARD or STANDARD_INFREQUENT_ACCESS. Switchable later at no cost/downtime — see docs/CostComparison.md."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "STANDARD_INFREQUENT_ACCESS"], var.table_class)
    error_message = "table_class must be either STANDARD or STANDARD_INFREQUENT_ACCESS."
  }
}

################################################################################
# Keys & Attributes
#
# The hash_key (+ range_key, if set) form the table's primary key and CANNOT
# be changed after creation — see docs/Analysis.md and docs/Glossary.md.
# Design these around your access patterns before applying.
################################################################################

variable "hash_key" {
  description = "Partition key attribute name"
  type        = string
}

variable "hash_key_type" {
  description = "Partition key attribute type: S (string), N (number), or B (binary)"
  type        = string
  default     = "S"
}

variable "range_key" {
  description = "Sort key attribute name. Leave empty for a partition-key-only table."
  type        = string
  default     = ""
}

variable "range_key_type" {
  description = "Sort key attribute type: S (string), N (number), or B (binary)"
  type        = string
  default     = "S"
}

variable "additional_attributes" {
  description = "Extra attributes needed only because a GSI/LSI keys on them (do not repeat hash_key/range_key here)"
  type = list(object({
    name = string
    type = string
  }))
  default = []
}

################################################################################
# Global Secondary Indexes (safe to add/remove after creation)
################################################################################

variable "global_secondary_indexes" {
  description = "GSIs for alternate access patterns. Can be added or removed after table creation (large tables incur a backfill period)."
  type = list(object({
    name               = string
    hash_key           = string
    range_key          = optional(string)
    projection_type    = string # ALL, KEYS_ONLY, or INCLUDE
    non_key_attributes = optional(list(string))
    read_capacity      = optional(number) # PROVISIONED mode only; defaults to var.read_capacity
    write_capacity     = optional(number) # PROVISIONED mode only; defaults to var.write_capacity
  }))
  default = []
}

################################################################################
# Local Secondary Indexes (must be decided at creation — cannot be changed later)
################################################################################

variable "local_secondary_indexes" {
  description = "LSIs. Must be defined at table creation and can never be added/changed/removed afterward. Also caps the table at 10GB per partition key value. Prefer a GSI unless you specifically need LSI's strongly-consistent-read behavior."
  type = list(object({
    name               = string
    range_key          = string
    projection_type    = string # ALL, KEYS_ONLY, or INCLUDE
    non_key_attributes = optional(list(string))
  }))
  default = []
}

################################################################################
# TTL, Streams, Recovery, Encryption (all safely toggleable later)
################################################################################

variable "enable_ttl" {
  description = "Enable item expiry via TTL"
  type        = bool
  default     = false
}

variable "ttl_attribute_name" {
  description = "Attribute holding the epoch-seconds expiry timestamp (only used if enable_ttl = true)"
  type        = string
  default     = "expires_at"
}

variable "enable_streams" {
  description = "Enable DynamoDB Streams (needed for CDC/Lambda triggers/Global Tables)"
  type        = bool
  default     = false
}

variable "stream_view_type" {
  description = "KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, or NEW_AND_OLD_IMAGES. Only used if enable_streams = true."
  type        = string
  default     = "NEW_AND_OLD_IMAGES"
}

variable "enable_point_in_time_recovery" {
  description = "Enable continuous backups / point-in-time recovery (35-day window). Recommended on for anything with real data."
  type        = bool
  default     = true
}

variable "enable_server_side_encryption" {
  description = "Enable encryption at rest"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN for encryption. Leave empty to use the AWS owned default key."
  type        = string
  default     = ""
}

variable "enable_deletion_protection" {
  description = "Prevent accidental table deletion via the API/console. Recommended for production."
  type        = bool
  default     = false
}

################################################################################
# Auto Scaling (PROVISIONED billing mode only)
################################################################################

variable "enable_autoscaling" {
  description = "Attach Application Auto Scaling to the table (and its GSIs) instead of a fixed provisioned capacity. Ignored unless billing_mode = PROVISIONED."
  type        = bool
  default     = false
}

variable "autoscaling_read_min" {
  description = "Minimum read capacity units"
  type        = number
  default     = 5
}

variable "autoscaling_read_max" {
  description = "Maximum read capacity units"
  type        = number
  default     = 100
}

variable "autoscaling_write_min" {
  description = "Minimum write capacity units"
  type        = number
  default     = 5
}

variable "autoscaling_write_max" {
  description = "Maximum write capacity units"
  type        = number
  default     = 100
}

variable "autoscaling_target_utilization" {
  description = "Target utilization percentage for auto scaling (AWS recommends 70%)"
  type        = number
  default     = 70
}

################################################################################
# Tags
################################################################################

variable "tags" {
  description = "Additional tags to apply to the table"
  type        = map(string)
  default     = {}
}
