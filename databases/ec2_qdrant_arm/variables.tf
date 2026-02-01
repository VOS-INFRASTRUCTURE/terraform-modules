################################################################################
# Variables for EC2 Qdrant ARM Module
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
  description = "Base name for the Qdrant instance (e.g., 'vector-db', 'qdrant')"
  type        = string
  default     = "qdrant"
}

################################################################################
# Instance Configuration
################################################################################

variable "ami_id" {
  description = "The AMI ID to use for the instance (leave empty to auto-detect latest Ubuntu 24.04 ARM64 for your region)"
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "The type of instance to launch (ARM/Graviton recommended for better price/performance)"
  type        = string
  default     = "t4g.large" # 2 vCPU, 8 GB RAM, ~$49/month
}

variable "subnet_id" {
  description = "The ID of the subnet where the instance will be launched (private subnet recommended)"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs to assign to the instance (must allow Qdrant ports: 6333 REST API, 6334 gRPC)"
  type        = list(string)
}

################################################################################
# Access Configuration
################################################################################
variable "key_name" {
  description = "SSH key pair name (optional, Session Manager recommended)"
  type        = string
  default     = ""
}

variable "enable_ssh_key_access" {
  description = "Enable SSH key access (false = Session Manager only, recommended for security)"
  type        = bool
  default     = false
}

variable "enable_ssm_access" {
  description = "Enable Systems Manager Session Manager for SSH-less access"
  type        = bool
  default     = true
}

################################################################################
# Storage Configuration
################################################################################

variable "storage_size" {
  description = "Size of the EBS volume in GB (Qdrant stores vector data, size based on collection size)"
  type        = number
  default     = 50
}

variable "storage_type" {
  description = "Type of EBS volume (gp3 recommended for cost and performance)"
  type        = string
  default     = "gp3"
}

variable "enable_ebs_encryption" {
  description = "Enable EBS volume encryption (recommended for production)"
  type        = bool
  default     = true
}

################################################################################
# Qdrant Configuration
################################################################################

variable "qdrant_api_key" {
  description = "API key for Qdrant REST/gRPC API authentication (leave empty to auto-generate)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "qdrant_read_only_api_key" {
  description = "Read-only API key for Qdrant (leave empty to auto-generate)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "qdrant_http_port" {
  description = "Qdrant REST API port"
  type        = number
  default     = 6333
}

variable "qdrant_grpc_port" {
  description = "Qdrant gRPC API port"
  type        = number
  default     = 6334
}

variable "qdrant_log_level" {
  description = "Qdrant log level (DEBUG, INFO, WARN, ERROR)"
  type        = string
  default     = "INFO"
}

################################################################################
# Backup Configuration
################################################################################

variable "enable_automated_backups" {
  description = "Enable automated Qdrant snapshots to S3"
  type        = bool
  default     = true
}

variable "backup_schedule" {
  description = "Cron schedule for backups (default: every 6 hours)"
  type        = string
  default     = "0 */6 * * *"
}

variable "create_backup_bucket" {
  description = "Create a new S3 bucket for backups (true) or use existing bucket (false)"
  type        = bool
  default     = true
}

variable "backup_s3_bucket_name" {
  description = "Name of existing S3 bucket for backups (only used if create_backup_bucket = false)"
  type        = string
  default     = ""
}

variable "backup_retention_days" {
  description = "Number of days to retain backups in S3"
  type        = number
  default     = 7
}

variable "enable_backup_versioning" {
  description = "Enable S3 versioning for backup bucket"
  type        = bool
  default     = false
}

################################################################################
# EBS Snapshot Configuration
################################################################################

variable "enable_ebs_snapshots" {
  description = "Enable automated EBS volume snapshots using AWS Data Lifecycle Manager"
  type        = bool
  default     = false
}

variable "ebs_snapshot_interval_hours" {
  description = "Interval in hours between EBS snapshots (12 or 24 recommended)"
  type        = number
  default     = 24
}

variable "ebs_snapshot_time" {
  description = "Time to take daily snapshots in UTC (HH:MM format, e.g., '03:00')"
  type        = string
  default     = "03:00"
}

variable "ebs_snapshot_retention_count" {
  description = "Number of EBS snapshots to retain (older snapshots are automatically deleted)"
  type        = number
  default     = 7
}

variable "enable_cross_region_snapshot_copy" {
  description = "Enable cross-region EBS snapshot copy for disaster recovery"
  type        = bool
  default     = false
}

variable "snapshot_dr_region" {
  description = "AWS region for disaster recovery snapshot copies"
  type        = string
  default     = ""
}

variable "snapshot_dr_retention_days" {
  description = "Number of days to retain DR snapshots in the target region"
  type        = number
  default     = 7
}

################################################################################
# Monitoring Configuration
################################################################################

variable "enable_cloudwatch_monitoring" {
  description = "Enable detailed CloudWatch monitoring and logging"
  type        = bool
  default     = true
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed EC2 monitoring (1-minute intervals, additional cost)"
  type        = bool
  default     = false
}

variable "cloudwatch_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 90
}

################################################################################
# Security Configuration
################################################################################

variable "enable_termination_protection" {
  description = "Enable EC2 termination protection (recommended for production)"
  type        = bool
  default     = false
}

################################################################################
# Tags
################################################################################

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

