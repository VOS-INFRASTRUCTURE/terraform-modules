################################################################################
# Variables for EC2 MySQL Module
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
  description = "Base name for the MySQL instance (e.g., 'db', 'mysql')"
  type        = string
  default     = "mysql"
}

################################################################################
# Instance Configuration
################################################################################

variable "ami_id" {
  description = "The AMI ID to use for the instance (leave empty to auto-detect latest Ubuntu 24.04 ARM64 for your region)"
  type        = string
  default     = ""
  # Auto-detection uses data source to find latest Ubuntu 24.04 ARM64 AMI
  # Only specify this if you need a specific AMI version
}

variable "instance_type" {
  description = "The type of instance to launch (ARM/Graviton recommended for better price/performance)"
  type        = string
  default     = "m7g.large" # 2 vCPU, 8 GB RAM, ~$67/month - Best for medium production workloads
  # Other good ARM options:
  # - t4g.medium: $24.53/month (burstable, good for staging)
  # - t4g.large: $49.06/month (burstable, small production)
  # - m7g.xlarge: $134.30/month (large production)
  # - r7g.large: $83.95/month (memory-heavy, 16GB RAM)
}

variable "subnet_id" {
  description = "The ID of the subnet where the instance will be launched (private subnet recommended)"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs to assign to the instance"
  type        = list(string)
}

variable "storage_size" {
  description = "The size of the root volume in GB"
  type        = number
  default     = 20
}

variable "storage_type" {
  description = "The type of storage to use for the root volume (gp3 recommended)"
  type        = string
  default     = "gp3"
}

variable "enable_ebs_encryption" {
  description = "Enable EBS volume encryption"
  type        = bool
  default     = true
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring (1-minute intervals)"
  type        = bool
  default     = false
}

variable "enable_termination_protection" {
  description = "Enable EC2 termination protection to prevent accidental deletion (recommended for production)"
  type        = bool
  default     = false
}

################################################################################
# Access Configuration
################################################################################

variable "key_name" {
  description = "EC2 key pair name for SSH access (optional if using SSM)"
  type        = string
  default     = ""
}

variable "enable_ssh_key_access" {
  description = "Enable SSH key access (set to false to use only SSM Session Manager)"
  type        = bool
  default     = false
}

variable "enable_ssm_access" {
  description = "Enable Systems Manager Session Manager for SSH-less access"
  type        = bool
  default     = true
}

################################################################################
# MySQL Configuration
################################################################################

variable "mysql_version" {
  description = "MySQL Docker image version (e.g., '8', '8.0', '8.0.35')"
  type        = string
  default     = "8.0"
}

variable "mysql_database" {
  description = "Name of the default MySQL database to create"
  type        = string
}

variable "mysql_user" {
  description = "MySQL username (non-root user for applications)"
  type        = string
}

variable "mysql_root_password" {
  description = "MySQL root password (leave empty to auto-generate and store in Secrets Manager)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "mysql_password" {
  description = "MySQL user password (leave empty to auto-generate and store in Secrets Manager)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "mysql_max_connections" {
  description = "Maximum number of simultaneous MySQL connections"
  type        = number
  default     = 200 # Good for m7g.large (8GB RAM) with connection pooling
}

variable "innodb_buffer_pool_size" {
  description = "InnoDB buffer pool size (75% of RAM recommended for dedicated MySQL servers)"
  type        = string
  default     = "6G" # 75% of 8GB RAM for m7g.large (dedicated MySQL server)
  # Adjust based on instance:
  # - t4g.medium (4GB): "3G"
  # - t4g.large (8GB): "6G"
  # - m7g.large (8GB): "6G" (default)
  # - m7g.xlarge (16GB): "12G"
  # - r7g.large (16GB): "12G"
}

################################################################################
# Monitoring & Logging
################################################################################

variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch logs and metrics"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
}

################################################################################
# Backup Configuration
################################################################################

variable "enable_automated_backups" {
  description = "Enable automated MySQL backups to S3"
  type        = bool
  default     = false
}

variable "create_backup_bucket" {
  description = "Create S3 bucket for backups (set to false if using existing bucket)"
  type        = bool
  default     = true
}

variable "backup_s3_bucket_name" {
  description = "S3 bucket name for MySQL backups (required if enable_automated_backups = true and create_backup_bucket = false)"
  type        = string
  default     = ""
}

variable "backup_schedule" {
  description = "Cron expression for backup schedule (e.g., '0 * * * *' for hourly, '0 2 * * *' for 2 AM daily)"
  type        = string
  default     = "0 * * * *"
}

variable "backup_retention_days" {
  description = "Number of days to retain backups in S3"
  type        = number
  default     = 7
}

variable "enable_backup_versioning" {
  description = "Enable S3 versioning for backup bucket (optional - backups use unique timestamps, so overwrites are unlikely)"
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
  description = "AWS region for disaster recovery snapshot copies (e.g., 'us-east-1', 'eu-west-1')"
  type        = string
  default     = ""
  # Common DR region pairs:
  # - eu-west-2 → us-east-1
  # - us-east-1 → us-west-2
  # - ap-southeast-1 → ap-northeast-1
}

variable "snapshot_dr_retention_days" {
  description = "Number of days to retain DR snapshots in the target region"
  type        = number
  default     = 7
}

################################################################################
# Tags
################################################################################

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

