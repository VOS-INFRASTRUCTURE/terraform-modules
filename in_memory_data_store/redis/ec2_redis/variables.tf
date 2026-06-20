################################################################################
# Variables for EC2 Redis Module
################################################################################

variable "env" {
  description = "Environment name (e.g., staging, production)"
  type        = string
}

variable "project_id" {
  description = "Project identifier for resource naming and tagging"
  type        = string
}

variable "base_name" {
  description = "Base name for the Redis instance (e.g., 'redis', 'cache')"
  type        = string
  default     = "redis"
}

variable "enable_ec2_redis" {
  description = "Whether to enable EC2 Redis instance"
  type        = bool
  default     = true
}

################################################################################
# Instance Configuration
################################################################################

variable "instance_type" {
  description = "EC2 instance type for Redis server (ARM64 only — t4g for burstable, r6g for memory-optimized)"
  type        = string
  default     = "t4g.micro"

  validation {
    condition = can(regex(
      "^(t4g\\.(nano|micro|small|medium)|r6g\\.(medium|large|xlarge|2xlarge))",
      var.instance_type
    ))
    error_message = "Must be a t4g (nano/micro/small/medium) or r6g (medium/large/xlarge/2xlarge) ARM64 instance."
  }
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance (leave empty to use latest Ubuntu 24.04 ARM64)"
  type        = string
  default     = ""
}

variable "root_volume_size" {
  description = "Size of root EBS volume in GB"
  type        = number
  default     = 8
}

variable "enable_ebs_encryption" {
  description = "Enable EBS volume encryption"
  type        = bool
  default     = true
}

################################################################################
# Network Configuration
################################################################################

variable "vpc_id" {
  description = "VPC ID where Redis instance will be deployed"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID where Redis instance will be deployed (should be private subnet)"
  type        = string
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to access Redis (application security groups)"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access Redis"
  type        = list(string)
  default     = []
}

variable "redis_port" {
  description = "Redis server port"
  type        = number
  default     = 6379
}

################################################################################
# Redis Configuration
################################################################################

variable "redis_version" {
  description = "Redis version to install. The module adds the Redis.io repository automatically. Valid: 6.2, 7.0, 7.2, 7.4, 8.0"
  type        = string
  default     = "8.0"

  validation {
    condition     = contains(["6.2", "7.0", "7.2", "7.4", "8.0"], var.redis_version)
    error_message = "Redis version must be one of: 6.2, 7.0, 7.2, 7.4, 8.0"
  }
}

variable "redis_max_memory" {
  description = "Max memory for Redis (e.g., '512mb', '1gb'). Default uses 75% of instance RAM"
  type        = string
  default     = "auto"
}

variable "redis_max_memory_policy" {
  description = "Redis eviction policy when max memory is reached"
  type        = string
  default     = "allkeys-lru"

  validation {
    condition = contains([
      "noeviction",
      "allkeys-lru",
      "allkeys-lfu",
      "allkeys-random",
      "volatile-lru",
      "volatile-lfu",
      "volatile-random",
      "volatile-ttl"
    ], var.redis_max_memory_policy)
    error_message = "Invalid Redis eviction policy"
  }
}

# Redis is used strictly as a cache.
# Persistence is disabled to reduce latency and cost.
variable "enable_redis_persistence" {
  description = "Enable Redis RDB persistence (snapshots)"
  type        = bool
  default     = false
}

variable "enable_redis_aof" {
  description = "Enable Redis AOF (append-only file) for durability"
  type        = bool
  default     = false
}

variable "redis_password" {
  description = "Redis password for authentication (leave empty for no password - not recommended)"
  type        = string
  default     = ""
  sensitive   = true
}

################################################################################
# Monitoring & Logging
################################################################################

variable "enable_cloudwatch_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for Redis"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
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
# Tags
################################################################################

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

