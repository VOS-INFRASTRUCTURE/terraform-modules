################################################################################
# ECS IAM CI/CD User Module - Variables
#
# Purpose: Define configurable parameters for creating a dedicated IAM user
#          with least-privilege permissions for ECS deployments via CI/CD.
################################################################################

################################################################################
# Required Variables
################################################################################

variable "user_name" {
  description = "Name for the IAM CI/CD user (e.g., 'staging-node-app-github-actions-ecs-deploy')"
  type        = string
}

variable "ecr_repository_arns" {
  description = "List of ECR repository ARNs that CI/CD user can push/pull images to/from"
  type        = list(string)
}

################################################################################
# Optional ECS Configuration
################################################################################

variable "enable_ecs_permissions" {
  description = "Whether to grant ECS deployment permissions (task definitions, service updates)"
  type        = bool
  default     = true
}

variable "ecs_cluster_arns" {
  description = "List of ECS cluster ARNs that CI/CD can deploy to (required if enable_ecs_permissions = true)"
  type        = list(string)
  default     = []
}

variable "ecs_service_arns" {
  description = "List of ECS service ARNs that CI/CD can update (required if enable_ecs_permissions = true)"
  type        = list(string)
  default     = []
}

variable "task_definition_family_prefixes" {
  description = "List of task definition family name prefixes (e.g., ['staging-ecs-node-app'])"
  type        = list(string)
  default     = []
}

variable "task_execution_role_arns" {
  description = "List of task execution role ARNs that CI/CD can pass to ECS (required if enable_ecs_permissions = true)"
  type        = list(string)
  default     = []
}

variable "task_role_arns" {
  description = "List of task role ARNs that CI/CD can pass to ECS (required if enable_ecs_permissions = true)"
  type        = list(string)
  default     = []
}

################################################################################
# Optional CloudWatch Logs Configuration
################################################################################

variable "enable_cloudwatch_logs_permissions" {
  description = "Whether to grant CloudWatch Logs read permissions for deployment verification"
  type        = bool
  default     = true
}

variable "log_group_arns" {
  description = "List of CloudWatch Log Group ARNs that CI/CD can read (required if enable_cloudwatch_logs_permissions = true)"
  type        = list(string)
  default     = []
}

################################################################################
# Access Key Configuration
################################################################################

variable "create_access_key" {
  description = "Whether to create an access key for the user (set to false if using OIDC/assume role)"
  type        = bool
  default     = true
}

variable "pgp_key" {
  description = "Optional PGP key (base64 encoded) to encrypt the secret access key"
  type        = string
  default     = null
}

################################################################################
# Tagging
################################################################################

variable "tags" {
  description = "Additional tags to apply to the IAM user"
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

################################################################################
# Advanced Configuration
################################################################################

variable "additional_policy_arns" {
  description = "List of additional IAM policy ARNs to attach to the user"
  type        = list(string)
  default     = []
}

variable "policy_name_prefix" {
  description = "Prefix for inline policy names"
  type        = string
  default     = "cicd"
}

variable "aws_region" {
  description = "AWS region for resource ARN construction (if not using data source)"
  type        = string
  default     = ""
}

variable "aws_account_id" {
  description = "AWS account ID for resource ARN construction (if not using data source)"
  type        = string
  default     = ""
}

