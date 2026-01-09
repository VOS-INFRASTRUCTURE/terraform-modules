################################################################################
# Module Variables: ECS Task Role
################################################################################

variable "project_id" {
  description = "Project identifier"
  type        = string
}

variable "env" {
  description = "Environment name (e.g., staging, production)"
  type        = string
}

variable "role_name" {
  description = "Name of the task role (optional, defaults to env-ecs-task-role)"
  type        = string
  default     = ""
}

variable "enable_ecs_exec" {
  description = "Enable ECS Exec permissions (SSM Session Manager for debugging)"
  type        = bool
  default     = true
}

variable "enable_s3_access" {
  description = "Enable S3 access permissions for the task"
  type        = bool
  default     = false
}

variable "s3_bucket_arns" {
  description = "List of S3 bucket ARNs to grant access to (required if enable_s3_access = true)"
  type        = list(string)
  default     = ["*"]
}

variable "enable_secrets_access" {
  description = "Enable Secrets Manager access permissions for the task"
  type        = bool
  default     = false
}

variable "secrets_arns" {
  description = "List of Secrets Manager secret ARNs to grant access to (required if enable_secrets_access = true)"
  type        = list(string)
  default     = []
}

variable "enable_parameter_store_access" {
  description = "Enable SSM Parameter Store access permissions for the task"
  type        = bool
  default     = false
}

variable "parameter_arns" {
  description = "List of SSM Parameter Store parameter ARNs to grant access to (required if enable_parameter_store_access = true)"
  type        = list(string)
  default     = []
}

