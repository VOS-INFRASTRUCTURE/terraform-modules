################################################################################
# Laravel Horizon ECS Task Definition - Variables
################################################################################

################################################################################
# Required Variables
################################################################################

variable "task_family" {
  description = "Name/family for the ECS task definition (e.g., 'staging-laravel-horizon-task')"
  type        = string
}

variable "container_name" {
  description = "Name for the Horizon container within the task definition"
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL for the Laravel app image (same image as the web task)"
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
  description = "ARN of the ECS task role (runtime permissions, e.g., SQS, S3 if jobs need them)"
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
# Resource Allocation
################################################################################

variable "cpu" {
  description = <<-EOT
    CPU units for the task. 1 vCPU = 1024 units. Valid: 256, 512, 1024, 2048, 4096.
    Pricing: ~$0.04656 per vCPU per hour (eu-west-2).
    Horizon workers are CPU-bound for compute-heavy jobs. Size based on job workload.
    Recommended starting point: 512 (0.5 vCPU) for typical queue work.
  EOT
  type        = string
  default     = "512"
}

variable "memory" {
  description = <<-EOT
    Memory in MiB for the task. Pricing: ~$0.00511 per GB per hour (eu-west-2).
    Recommended starting point: 1024 MiB. Increase if jobs process large datasets.
    Valid ranges depend on CPU — see AWS Fargate docs.
  EOT
  type        = string
  default     = "1024"
}

################################################################################
# Secrets & Environment Variables
################################################################################

variable "secrets" {
  description = <<-EOT
    Secrets from SSM Parameter Store or Secrets Manager.
    Format: [{ name = "REDIS_PASSWORD", valueFrom = "arn:aws:ssm:..." }]
    These are fetched at container startup by the execution role.
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
    Format: [{ name = "QUEUE_CONNECTION", value = "redis" }]
    Use secrets for sensitive values — never put credentials here.
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
# Health Check
################################################################################

variable "health_check_enabled" {
  description = "Enable container health check. Useful for ECS to detect a stuck Horizon process."
  type        = bool
  default     = true
}

variable "health_check_command" {
  description = <<-EOT
    Shell command to verify Horizon is running inside the container.

    Default checks that supervisorctl reports the horizon program as RUNNING.
    This requires supervisord to be running and the program named 'horizon'
    in your supervisord.conf.

    Alternatives:
    - "php artisan horizon:status | grep -qi running || exit 1"
      (requires Laravel app to be bootable — slower but checks the queue connection)
    - "pidof php > /dev/null || exit 1"
      (lightweight, but only confirms php is running, not Horizon specifically)
  EOT
  type        = string
  default     = "supervisorctl status horizon | grep -q RUNNING || exit 1"
}

variable "health_check_interval" {
  description = "Seconds between health checks"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Seconds to wait for the health check command to complete"
  type        = number
  default     = 10
}

variable "health_check_retries" {
  description = "Consecutive failures before the container is marked unhealthy"
  type        = number
  default     = 3
}

variable "health_check_start_period" {
  description = <<-EOT
    Grace period in seconds before health check failures count.
    Horizon needs time to connect to Redis and start workers after the container starts.
    Increase if your app takes a long time to boot (e.g., large cache warm-ups).
  EOT
  type        = number
  default     = 120
}

################################################################################
# Graceful Shutdown
################################################################################

variable "stop_timeout" {
  description = <<-EOT
    Seconds ECS waits after sending SIGTERM before force-killing the container.
    Must be long enough for your slowest job to finish processing.
    Horizon sends SIGTERM to workers when it receives SIGTERM itself, so in-flight
    jobs finish before Horizon exits.

    Default: 120 seconds (2 minutes). Set higher if you have long-running jobs.
    Maximum allowed by ECS Fargate: 120 seconds.

    Note: The supervisord stopwaitsecs in your supervisord.conf must be >= this value.
  EOT
  type        = number
  default     = 120
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
