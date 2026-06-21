################################################################################
# Laravel Web ECS Task Definition - Variables
################################################################################

################################################################################
# Required Variables
################################################################################

variable "task_family" {
  description = "Name/family for the ECS task definition (e.g., 'staging-laravel-web-task')"
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL for the Laravel app image used by the php-fpm container"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag for the Laravel app (use commit SHA or build number — NOT 'latest')"
  type        = string
}

variable "execution_role_arn" {
  description = "ARN of the ECS task execution role (pulls images from ECR, fetches secrets)"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS task role (runtime permissions for the application)"
  type        = string
}

variable "region" {
  description = "AWS region for CloudWatch logs (e.g., 'eu-west-2')"
  type        = string
}

variable "log_group_name" {
  description = "Name for the CloudWatch log group (shared by nginx and php-fpm streams)"
  type        = string
}

################################################################################
# Container Names
################################################################################

variable "container_name_nginx" {
  description = "Name for the nginx container within the task definition"
  type        = string
  default     = "nginx"
}

variable "container_name_php_fpm" {
  description = "Name for the php-fpm container within the task definition"
  type        = string
  default     = "php-fpm"
}

################################################################################
# Image Configuration
################################################################################

variable "nginx_image" {
  description = <<-EOT
    Full Docker image URI for the nginx container.
    Must be built from Dockerfile.nginx in the application repo — it bakes in the
    nginx config template and compiled frontend assets (CSS/JS).
    Example: "123456789.dkr.ecr.eu-west-2.amazonaws.com/my-nginx:abc1234"
  EOT
  type        = string
}

################################################################################
# Port Configuration
################################################################################

variable "container_port" {
  description = "Port that nginx exposes (the ALB target group must match this)"
  type        = number
  default     = 80
}

################################################################################
# Resource Allocation
################################################################################

variable "cpu" {
  description = <<-EOT
    Total CPU units for the task (shared across all containers).
    1 vCPU = 1024 units. Valid: 256, 512, 1024, 2048, 4096.
    Pricing: ~$0.04656 per vCPU per hour (eu-west-2).
    Recommended for Laravel web: 512–1024 (accommodates both nginx and php-fpm).
  EOT
  type        = string
  default     = "512"
}

variable "memory" {
  description = <<-EOT
    Total memory in MiB for the task (shared across all containers).
    Pricing: ~$0.00511 per GB per hour (eu-west-2).
    Recommended for Laravel web: 1024–2048 MiB.
    Valid ranges depend on CPU — see AWS Fargate docs.
  EOT
  type        = string
  default     = "1024"
}

################################################################################
# Secrets & Environment Variables (injected into php-fpm only)
################################################################################

variable "secrets" {
  description = <<-EOT
    Secrets for the php-fpm container from SSM Parameter Store or Secrets Manager.
    Format: [{ name = "APP_KEY", valueFrom = "arn:aws:ssm:..." }]
    Fetched by the execution role at container startup.
  EOT
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "environment_variables" {
  description = <<-EOT
    Static environment variables for the php-fpm container.
    Format: [{ name = "APP_ENV", value = "production" }]
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
  description = "Number of days to retain logs in CloudWatch"
  type        = number
  default     = 30
}

variable "log_stream_prefix" {
  description = "Prefix for CloudWatch log streams (nginx streams as <prefix>/nginx, php-fpm as <prefix>/php-fpm)"
  type        = string
  default     = "ecs"
}

################################################################################
# Health Check — nginx
################################################################################

variable "health_check_enabled" {
  description = "Enable health check on the nginx container (checked by ALB and ECS)"
  type        = bool
  default     = true
}

variable "health_check_endpoint" {
  description = "HTTP path nginx uses for its health check (e.g., '/health' or '/ping')"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Seconds between health checks (applies to both nginx and php-fpm checks)"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Seconds to wait for a health check response"
  type        = number
  default     = 5
}

variable "health_check_retries" {
  description = "Consecutive failures before a container is marked unhealthy"
  type        = number
  default     = 3
}

variable "health_check_start_period" {
  description = "Grace period in seconds before health check failures count (allow Laravel to boot)"
  type        = number
  default     = 60
}

################################################################################
# Health Check — php-fpm
################################################################################

variable "php_fpm_health_check_command" {
  description = <<-EOT
    Shell command used to health-check the php-fpm container.
    nginx's dependsOn waits for this to pass before nginx starts.

    Default uses 'pidof php-fpm' which works in all standard php:*-fpm images.

    Alternatives:
    - php-fpm-healthcheck (requires the script installed in your image)
    - cgi-fcgi (requires libfcgi-bin and a status page configured in php-fpm.conf)

    Example with php-fpm status page:
      "SCRIPT_NAME=/status SCRIPT_FILENAME=/status REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 > /dev/null"
  EOT
  type        = string
  default     = "pidof php-fpm > /dev/null || exit 1"
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
