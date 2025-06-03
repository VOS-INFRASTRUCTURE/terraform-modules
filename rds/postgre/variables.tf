
# inputs.tf
variable "subnet_ids" {
  description = "List of subnet IDs for the RDS instance"
  type        = list(string)
}

variable "allocated_storage" {
  description = "Allocated storage for the RDS instance in GB"
  type        = number
}

variable "max_allocated_storage" {
  description = "Maximum allocated storage for the RDS instance in GB"
  type        = number
}

variable "db_engine_version" {
  description = "Database engine version for the PostgreSQL RDS instance"
  type        = string
}

variable "db_instance_class" {
  description = "Instance class for the RDS instance"
  type        = string
}

variable "db_name" {
  description = "Database name for the RDS instance"
  type        = string
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
}

variable "db_password" {
  description = "Master password for the RDS instance"
  type        = string
}

variable "vpc_security_group_ids" {
  description = "List of VPC security group IDs for the RDS instance"
  type        = list(string)
}

variable "multi_az" {
  description = "Whether the RDS instance is multi-AZ"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Whether to skip the final snapshot on RDS instance deletion"
  type        = bool
  default     = true
}

variable "publicly_accessible" {
  description = "Whether the RDS instance is publicly accessible"
  type        = bool
  default     = false
}

variable "env" {
  description = "Environment for tagging and naming (e.g., staging, production)"
  type        = string
}

variable "project_id" {
  description = "Project ID where all project resources exists"
}
