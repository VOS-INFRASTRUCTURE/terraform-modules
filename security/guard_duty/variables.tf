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
#
# Note: All features are enabled via aws_guardduty_detector_feature resources
#       The old datasources {} block is deprecated.
################################################################################

variable "enable_s3_data_events" {
  description = "Enable S3 data events monitoring (monitors S3 object-level API calls for suspicious activity). Cost: ~$0.20/GB analyzed"
  type        = bool
  default     = true
}

variable "enable_eks_audit_logs" {
  description = "Enable EKS audit logs monitoring (analyzes Kubernetes API audit logs). Cost: ~$0.012/GB. Only enable if you have EKS clusters."
  type        = bool
  default     = false  # Only enable if you have EKS clusters
}

variable "enable_rds_protection" {
  description = "Enable RDS login activity monitoring (monitors database login attempts). Cost: Included in base GuardDuty pricing."
  type        = bool
  default     = true
}

variable "enable_lambda_protection" {
  description = "Enable Lambda network activity monitoring (monitors Lambda function network activity). Cost: Included in base GuardDuty pricing."
  type        = bool
  default     = true
}

variable "enable_ebs_malware_protection" {
  description = "Enable EC2/EBS malware protection - GuardDuty-initiated scans (scans EBS volumes when suspicious activity is detected). Cost: $0.10/GB scanned (only when triggered)."
  type        = bool
  default     = true
}

variable "enable_s3_malware_protection" {
  description = "Enable S3 malware scanning (scans new S3 uploads for malware). Cost: Varies by usage. Note: This is different from enable_s3_data_events which monitors access patterns."
  type        = bool
  default     = false  # Disabled by default due to additional cost
}

variable "enable_runtime_monitoring" {
  description = "Enable Runtime Monitoring base feature (required for EKS/ECS Fargate/EC2 runtime monitoring). This only enables the feature - you must also enable agent deployment per platform. Cost: Varies by usage."
  type        = bool
  default     = false  # Only enable if you have EKS clusters, ECS Fargate tasks, or EC2 instances
}

variable "enable_eks_runtime_agent" {
  description = "Enable automated agent deployment for EKS clusters. Requires enable_runtime_monitoring = true. This is the ONLY runtime agent that can be automated via Terraform."
  type        = bool
  default     = false  # Only enable if you have EKS clusters
}




