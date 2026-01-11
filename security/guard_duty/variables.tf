################################################################################
# GuardDuty Module Variables
################################################################################

################################################################################
# General Configuration
################################################################################

variable "enable_guardduty" {
  description = "Enable or disable GuardDuty. Set to false to disable all GuardDuty resources."
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
# GuardDuty Detector Configuration
################################################################################

variable "finding_publishing_frequency" {
  description = "Frequency for publishing findings to CloudWatch Events"
  type        = string
  default     = "FIFTEEN_MINUTES"

  validation {
    condition = contains([
      "FIFTEEN_MINUTES",
      "ONE_HOUR",
      "SIX_HOURS"
    ], var.finding_publishing_frequency)
    error_message = "Finding publishing frequency must be one of: FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS"
  }
}

################################################################################
# GuardDuty Protection Features
#
# Toggle individual protection capabilities for cost optimization.
# Each feature adds additional monitoring and costs.
################################################################################

variable "enable_s3_protection" {
  description = "Enable S3 protection (monitors S3 data events for suspicious activity)"
  type        = bool
  default     = true
}

variable "enable_eks_protection" {
  description = "Enable EKS protection (monitors Kubernetes audit logs)"
  type        = bool
  default     = false  # Only enable if you have EKS clusters
}

variable "enable_malware_protection" {
  description = "Enable malware protection (scans EBS volumes when suspicious activity is detected)"
  type        = bool
  default     = true
}

variable "enable_rds_protection" {
  description = "Enable RDS protection (monitors database login activity)"
  type        = bool
  default     = true
}

variable "enable_lambda_protection" {
  description = "Enable Lambda protection (monitors Lambda network activity)"
  type        = bool
  default     = true
}

################################################################################
# Advanced GuardDuty Features (Detector Features)
#
# These are advanced features that require explicit enabling via detector_feature
# resources. They provide additional threat detection beyond the base detector.
################################################################################

variable "enable_s3_data_events" {
  description = "Enable S3 data events monitoring (additional S3 protection beyond base S3 protection)"
  type        = bool
  default     = false  # Additional cost - enable if you need granular S3 monitoring
}

variable "enable_eks_audit_logs" {
  description = "Enable EKS audit logs monitoring (requires EKS clusters)"
  type        = bool
  default     = false  # Only enable if you have EKS clusters
}

variable "enable_ebs_malware_protection" {
  description = "Enable EBS malware protection (scans EBS volumes for malware)"
  type        = bool
  default     = false  # Additional cost - enable for high-security environments
}

