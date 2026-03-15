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
  default     = "t3a.medium"
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

################################################################################
# Tags
################################################################################

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

