################################################################################
# Laravel Scheduler ECS Task Definition - Variables
################################################################################

################################################################################
# Required Variables
################################################################################

variable "task_family" {
  description = "Name/family for the ECS task definition (e.g., 'staging-laravel-scheduler-task')"
  type        = string
}

variable "container_name" {
  description = "Name for the scheduler container within the task definition"
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL for the Laravel app image (same image as web and horizon tasks)"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag (use commit SHA or build number — NOT 'latest')"
  type        = string
}

variable "execution_role_arn" {
  description = "ARN of the ECS task execution role (pulls images from ECR, fetches secrets)"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS task role (runtime permissions, e.g., S3 if commands need it)"
  type        = string
}

variable "region" {
  description = "AWS region for CloudWatch logs (e.g., 'eu-west-2')"
  type        = string
}

variable "log_group_name" {
  description = "Name for the CloudWatch log group"
  type        = string
}

################################################################################
# Scheduler Command
################################################################################

variable "scheduler_command" {
  description = <<-EOT
    Command that overrides the container image's default CMD/ENTRYPOINT.
    Runs php artisan schedule:run from the Laravel project root.

    Change if your Dockerfile uses a different working directory or php path:
    Example: ["/usr/local/bin/php", "/app/artisan", "schedule:run"]
  EOT
  type        = list(string)
  default     = ["php", "artisan", "schedule:run"]
}

################################################################################
# Resource Allocation
################################################################################

variable "cpu" {
  description = <<-EOT
    CPU units for the task. 1 vCPU = 1024 units. Valid: 256, 512, 1024, 2048, 4096.
    Pricing: ~$0.04656 per vCPU per hour (eu-west-2).
    The scheduler task runs for ~5–15 seconds, so even at 256 the cost is negligible.
    Recommended: 256 (enough for schedule:run and dispatching jobs to Redis).
  EOT
  type        = string
  default     = "256"
}

variable "memory" {
  description = <<-EOT
    Memory in MiB for the task. Pricing: ~$0.00511 per GB per hour (eu-west-2).
    Recommended: 512 MiB (scheduler only bootstraps Laravel and dispatches jobs).
    Increase if an inline command (not a queued job) loads large datasets.
  EOT
  type        = string
  default     = "512"
}

################################################################################
# Secrets & Environment Variables
################################################################################

variable "secrets" {
  description = <<-EOT
    Secrets from SSM Parameter Store or Secrets Manager.
    Format: [{ name = "REDIS_PASSWORD", valueFrom = "arn:aws:ssm:..." }]
    The scheduler needs the same secrets as the web task (DB, Redis, etc.).
  EOT
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "environment_variables" {
  description = <<-EOT
    Static environment variables.
    Format: [{ name = "APP_ENV", value = "production" }]
    Use secrets for sensitive values.
  EOT
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

################################################################################
# Logging
################################################################################

variable "log_retention_days" {
  description = "Days to retain logs in CloudWatch"
  type        = number
  default     = 30
}

variable "log_stream_prefix" {
  description = "Prefix for CloudWatch log streams"
  type        = string
  default     = "ecs"
}

################################################################################
# Security
################################################################################

variable "enable_readonly_root_filesystem" {
  description = <<-EOT
    Mount the root filesystem as read-only (Security Hub ECS.8 requirement).
    When true, ephemeral volumes are mounted at /tmp and /var/run.
    The scheduler command itself does not write to disk, so this is safe to enable.
    Set to false only if an inline scheduled command writes outside /tmp.
  EOT
  type        = bool
  default     = true
}

################################################################################
# Tagging
################################################################################

variable "tags" {
  description = "Additional tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "environment" {
  description = "Environment name (e.g., 'staging', 'production') — added as Environment tag"
  type        = string
  default     = ""
}

variable "project_id" {
  description = "Project identifier — added as Project tag"
  type        = string
  default     = ""
}
