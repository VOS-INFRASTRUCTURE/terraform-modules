################################################################################

variable "project_id" {
  # Use a simple, lowercase identifier without spaces or special characters
  description = "Project identifier like myapp"
  type        = string
}

variable "env" {
  description = "Environment name (e.g., staging, production)"
  type        = string
}

variable "repo_suffix_name" {
  description = "ECR repository suffix name like ecs-node-app"
  type        = string
}

variable "image_tag_mutability" {
  description = "Tag mutability for ECR images"
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "lifecycle_keep_last_count" {
  description = "Number of most recent images to keep (older images will be deleted)"
  type        = number
  default     = 10
}
