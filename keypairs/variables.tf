variable "env" {
  description = "Environment for tagging and naming (e.g., staging, production)"
  type        = string
}

variable "project_id" {
  description = "Project ID where all project resources exists"
}

variable "vpc_id" {
  description = "The VPC ID the key belongs to"
  type        = string
}
