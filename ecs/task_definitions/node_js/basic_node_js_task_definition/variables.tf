################################################################################
# Basic Node.js ECS Task Definition - Variables
#
# Purpose: Define configurable parameters for creating a reusable Node.js
#          ECS task definition with Fargate compatibility.
################################################################################

################################################################################
# Required Variables
################################################################################

variable "task_family" {
  description = "Name/family for the ECS task definition (e.g., 'staging-ecs-node-app-task')"
  type        = string
}

variable "container_name" {
  description = "Name for the container within the task definition"
  type        = string
}

variable "ecr_repository_url" {
  description = "URL of the ECR repository containing the Docker image"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag for the Node.js app (use commit SHA, version, or build number - NOT 'latest')"
  type        = string
}

variable "execution_role_arn" {
  description = "ARN of the ECS task execution role (for pulling images and fetching secrets)"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS task role (for application runtime permissions)"
  type        = string
}

variable "region" {
  description = "AWS region for CloudWatch logs"
  type        = string
}

################################################################################
# Container Configuration
################################################################################

variable "container_port" {
  description = "Port that the container exposes"
  type        = number
  default     = 3000
}

variable "container_protocol" {
  description = "Protocol for the container port"
  type        = string
  default     = "tcp"
}

################################################################################
# Resource Allocation
################################################################################

variable "cpu" {
  description = <<-EOT
    CPU allocation in CPU units (1 vCPU = 1024 units)
    Valid values: 256 (.25 vCPU), 512 (.5 vCPU), 1024 (1 vCPU), 2048 (2 vCPU), 4096 (4 vCPU)
    Pricing: ~$0.04656 per vCPU per hour (EU-West-2)
  EOT
  type        = string
  default     = "256"
}

variable "memory" {
  description = <<-EOT
    Memory allocation in MiB (Mebibytes)
    Valid memory values depend on CPU:
    - 256 CPU: 512 MiB to 2048 MiB (0.5 GB to 2 GB)
    - 512 CPU: 1024 MiB to 4096 MiB (1 GB to 4 GB)
    - 1024 CPU: 2048 MiB to 8192 MiB (2 GB to 8 GB)
    - 2048 CPU: 4096 MiB to 16384 MiB (4 GB to 16 GB)
    - 4096 CPU: 8192 MiB to 30720 MiB (8 GB to 30 GB)
    Pricing: ~$0.00511 per GB per hour (EU-West-2)
  EOT
  type        = string
  default     = "1024"
}

################################################################################
# Secrets & Environment Variables
################################################################################

variable "secrets" {
  description = <<-EOT
    List of secrets to inject from SSM Parameter Store or Secrets Manager.
    Format: [{ name = "ENV_VAR_NAME", valueFrom = "arn:aws:ssm:..." }]
    These are fetched at container startup by the Task Execution Role.
  EOT
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "environment_variables" {
  description = <<-EOT
    List of static environment variables.
    Format: [{ name = "ENV_VAR_NAME", value = "some-value" }]
    Use this for values that rarely change and don't need AWS Console updates.
  EOT
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

################################################################################
# Logging Configuration
################################################################################

variable "log_group_name" {
  description = "Name for the CloudWatch log group (will be created if create_log_group is true)"
  type        = string
}


variable "log_retention_days" {
  description = "Number of days to retain logs in CloudWatch"
  type        = number
  default     = 30
}

variable "log_stream_prefix" {
  description = "Prefix for CloudWatch log streams"
  type        = string
  default     = "ecs"
}

################################################################################
# Health Check Configuration
################################################################################

variable "health_check_enabled" {
  description = "Whether to enable container health checks"
  type        = bool
  default     = true
}

variable "health_check_endpoint" {
  description = "HTTP endpoint path for health checks (e.g., '/health')"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Time between health checks (in seconds)"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Time to wait for health check response (in seconds)"
  type        = number
  default     = 5
}

variable "health_check_retries" {
  description = "Number of consecutive failures before marking unhealthy"
  type        = number
  default     = 3
}

variable "health_check_start_period" {
  description = "Grace period for container startup before health checks count (in seconds)"
  type        = number
  default     = 60
}

################################################################################
# Tagging
################################################################################

variable "tags" {
  description = "Tags to apply to all resources created by this module"
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

