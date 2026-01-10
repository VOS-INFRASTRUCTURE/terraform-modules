################################################################################
# ECS Service Autoscaling Module - Variables
#
# Purpose: Define configurable parameters for ECS service autoscaling
################################################################################

################################################################################
# Required Variables
################################################################################

variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "ecs_service_name" {
  description = "Name of the ECS service to scale (from aws_ecs_service.name)"
  type        = string
}

################################################################################
# Capacity Configuration
################################################################################

variable "min_capacity" {
  description = "Minimum number of tasks (always at least this many running for availability)"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of tasks (cost protection, prevents runaway scaling)"
  type        = number
  default     = 10
}

################################################################################
# CPU-Based Scaling Configuration
################################################################################

variable "enable_cpu_scaling" {
  description = "Enable CPU-based autoscaling"
  type        = bool
  default     = true
}

variable "cpu_target_value" {
  description = <<-EOT
    Target CPU utilization percentage for autoscaling.
    50% = Conservative (more headroom, higher cost)
    70% = Balanced (recommended)
    85% = Aggressive (lower cost, less headroom)
  EOT
  type        = number
  default     = 70.0
}

variable "cpu_scale_in_cooldown" {
  description = "Wait time (seconds) before removing tasks to prevent flapping. 300s (5 min) recommended."
  type        = number
  default     = 300
}

variable "cpu_scale_out_cooldown" {
  description = "Wait time (seconds) before adding tasks. 60s (1 min) recommended for quick response."
  type        = number
  default     = 60
}

################################################################################
# Memory-Based Scaling Configuration
################################################################################

variable "enable_memory_scaling" {
  description = "Enable memory-based autoscaling (optional, works alongside CPU scaling)"
  type        = bool
  default     = true
}

variable "memory_target_value" {
  description = "Target memory utilization percentage. Usually higher than CPU (e.g., 80%) to avoid premature scaling."
  type        = number
  default     = 80.0
}

variable "memory_scale_in_cooldown" {
  description = "Wait time (seconds) before removing tasks based on memory"
  type        = number
  default     = 300
}

variable "memory_scale_out_cooldown" {
  description = "Wait time (seconds) before adding tasks based on memory"
  type        = number
  default     = 60
}

################################################################################
# ALB Request Count Scaling Configuration
################################################################################

variable "enable_request_count_scaling" {
  description = "Enable ALB request count-based autoscaling"
  type        = bool
  default     = false
}

variable "request_count_target_value" {
  description = "Target requests per task per minute. Example: 1000 = each task handles 1000 req/min"
  type        = number
  default     = 1000.0
}

variable "request_count_scale_in_cooldown" {
  description = "Wait time (seconds) before removing tasks based on request count"
  type        = number
  default     = 300
}

variable "request_count_scale_out_cooldown" {
  description = "Wait time (seconds) before adding tasks based on request count"
  type        = number
  default     = 60
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (required if enable_request_count_scaling = true). Format: app/name/id"
  type        = string
  default     = ""
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix (required if enable_request_count_scaling = true). Format: targetgroup/name/id"
  type        = string
  default     = ""
}

################################################################################
# Scheduled Scaling Configuration
################################################################################

variable "enable_scheduled_scaling" {
  description = "Enable scheduled scaling for predictable workloads"
  type        = bool
  default     = false
}

variable "scheduled_actions" {
  description = <<-EOT
    List of scheduled scaling actions.
    Format: [
      {
        name         = "scale-up-business-hours"
        schedule     = "cron(0 8 * * MON-FRI *)"  # 8 AM weekdays
        min_capacity = 3
        max_capacity = 10
      }
    ]
  EOT
  type = list(object({
    name         = string
    schedule     = string
    min_capacity = number
    max_capacity = number
  }))
  default = []
}

################################################################################
# CloudWatch Alarms Configuration
################################################################################

variable "enable_scaling_alarms" {
  description = "Create CloudWatch alarms for scaling events"
  type        = bool
  default     = false
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications (required if enable_scaling_alarms = true)"
  type        = string
  default     = ""
}

################################################################################
# Tagging
################################################################################

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "environment" {
  description = "Environment name (e.g., 'staging', 'production') - added to default tags"
  type        = string
  default     = ""
}

variable "project_id" {
  description = "Project identifier - added to default tags"
  type        = string
  default     = ""
}

