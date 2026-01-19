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
  description = "The AMI ID to use for the instance (Ubuntu 22.04 recommended)"
  type        = string
  default = "ami-05c172c7f0d3aed00" # Canonical, Ubuntu, 24.04, amd64 image
}

variable "instance_type" {
  description = "The type of instance to launch (e.g., t3.micro, t3.small, t3.medium)"
  type        = string
  default     = "t3.micro"
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
  default     = 151
}

variable "innodb_buffer_pool_size" {
  description = "InnoDB buffer pool size (e.g., '128M', '256M', '512M', '1G')"
  type        = string
  default     = "128M"
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

################################################################################
# Tags
################################################################################

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

