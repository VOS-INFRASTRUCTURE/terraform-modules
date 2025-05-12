variable "environment" {
  description = "Environment for tagging and naming (e.g., staging, production)"
  type        = string
  default     = "staging"
}

variable "bucket_base_name" {
  description = "Base name of the S3 bucket"
  type        = string
}

variable "project_id" {
  description = "Project ID where all project resources exists"
}

variable "region" {
  description = "AWS region where the bucket is created"
  type        = string
}
