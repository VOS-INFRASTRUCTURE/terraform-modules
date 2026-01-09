
variable "project_id" {
  description = "Project identifier"
  type        = string
}

variable "env" {
  description = "Environment name (e.g., staging, production)"
  type        = string
}

variable "role_name" {
  description = "Name of the task execution role (optional, defaults to env-ecs-task-execution-role)"
  type        = string
  default     = ""
}

variable "enable_secrets_access" {
  description = "Enable access to Secrets Manager and SSM Parameter Store"
  type        = bool
  default     = true
}