################################################################################
# Variables for ElastiCache Redis Module
################################################################################

variable "env" {
  description = "Environment name (e.g., staging, production)"
  type        = string
}

variable "project_id" {
  description = "Project identifier for resource naming and tagging"
  type        = string
}

variable "enable_elasticache" {
  description = "Whether to enable ElastiCache Redis cluster"
  type        = bool
  default     = true
}

################################################################################
# Cluster Configuration
################################################################################

variable "engine" {
  description = "Redis engine: 'redis' (Redis OSS) or 'valkey' (AWS fork, 30% cheaper)"
  type        = string
  default     = "valkey"

  validation {
    condition     = contains(["redis", "valkey"], var.engine)
    error_message = "Engine must be 'redis' or 'valkey'"
  }
}

variable "engine_version" {
  description = "Redis/Valkey engine version (e.g., '7.1' for Valkey, '7.0' for Redis)"
  type        = string
  default     = "7.1"
}

variable "node_type" {
  description = "ElastiCache node instance type (e.g., cache.t4g.micro, cache.t4g.small)"
  type        = string
  default     = "cache.t4g.micro"

  validation {
    condition     = can(regex("^cache\\.(t4g|t3|r7g|r6g|m7g|m6g)\\.(micro|small|medium|large|xlarge|2xlarge)", var.node_type))
    error_message = "Node type must be a valid ElastiCache instance type"
  }
}

variable "port" {
  description = "Port number for Redis/Valkey"
  type        = number
  default     = 6379
}

################################################################################
# High Availability Configuration
################################################################################

variable "num_cache_nodes" {
  description = "Number of cache nodes (1 = single node, 2+ = HA with replicas). Use 2 for production HA."
  type        = number
  default     = 1

  validation {
    condition     = var.num_cache_nodes >= 1 && var.num_cache_nodes <= 6
    error_message = "Number of cache nodes must be between 1 and 6"
  }
}

variable "automatic_failover_enabled" {
  description = "Enable automatic failover (requires num_cache_nodes >= 2 and cluster_mode_enabled = false for replication group)"
  type        = bool
  default     = false
}

variable "multi_az_enabled" {
  description = "Enable Multi-AZ with automatic failover (requires automatic_failover_enabled = true)"
  type        = bool
  default     = false
}

################################################################################
# Cluster Mode Configuration
################################################################################

variable "cluster_mode_enabled" {
  description = "Enable cluster mode (sharding). For most use cases, keep this false (disabled)."
  type        = bool
  default     = false
}

variable "num_node_groups" {
  description = "Number of node groups (shards) for cluster mode. Only used if cluster_mode_enabled = true."
  type        = number
  default     = 1
}

variable "replicas_per_node_group" {
  description = "Number of replicas per node group. Only used if cluster_mode_enabled = true."
  type        = number
  default     = 1
}

################################################################################
# Network Configuration
################################################################################

variable "vpc_id" {
  description = "VPC ID where ElastiCache will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for ElastiCache subnet group (use private subnets, minimum 2 for Multi-AZ)"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to access ElastiCache (application security groups)"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access ElastiCache"
  type        = list(string)
  default     = []
}

################################################################################
# Security Configuration
################################################################################

variable "at_rest_encryption_enabled" {
  description = "Enable encryption at rest"
  type        = bool
  default     = true
}

variable "transit_encryption_enabled" {
  description = "Enable encryption in transit (TLS)"
  type        = bool
  default     = false
}

variable "auth_token" {
  description = "Password for Redis AUTH (leave empty for no password). Required if transit_encryption_enabled = true."
  type        = string
  default     = ""
  sensitive   = true
}

variable "auth_token_update_strategy" {
  description = "Strategy for updating auth token: ROTATE or SET"
  type        = string
  default     = "ROTATE"

  validation {
    condition     = contains(["ROTATE", "SET"], var.auth_token_update_strategy)
    error_message = "Auth token update strategy must be ROTATE or SET"
  }
}

################################################################################
# Backup & Maintenance Configuration
################################################################################

variable "snapshot_retention_limit" {
  description = "Number of days to retain automatic snapshots (0 = disabled, max 35)"
  type        = number
  default     = 5

  validation {
    condition     = var.snapshot_retention_limit >= 0 && var.snapshot_retention_limit <= 35
    error_message = "Snapshot retention must be between 0 and 35 days"
  }
}

variable "snapshot_window" {
  description = "Daily time range for automated snapshots (UTC, e.g., '03:00-05:00')"
  type        = string
  default     = "03:00-05:00"
}

variable "final_snapshot_identifier" {
  description = "Name of final snapshot when cluster is deleted (leave empty to skip final snapshot)"
  type        = string
  default     = ""
}

variable "maintenance_window" {
  description = "Weekly time range for maintenance (UTC, e.g., 'sun:05:00-sun:06:00')"
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "apply_immediately" {
  description = "Apply changes immediately instead of during maintenance window"
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "Enable automatic minor version upgrades during maintenance window"
  type        = bool
  default     = true
}

################################################################################
# Performance & Monitoring Configuration
################################################################################

variable "parameter_group_family" {
  description = "Redis/Valkey parameter group family (e.g., 'valkey7', 'redis7')"
  type        = string
  default     = "valkey7"
}

variable "custom_parameters" {
  description = "Custom Redis/Valkey parameters to override defaults"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "notification_topic_arn" {
  description = "ARN of SNS topic for ElastiCache notifications"
  type        = string
  default     = ""
}

variable "log_delivery_configuration" {
  description = "Log delivery configuration for slow-log and engine-log"
  type = list(object({
    destination      = string
    destination_type = string
    log_format       = string
    log_type         = string
  }))
  default = []
}

################################################################################
# Tags
################################################################################

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

