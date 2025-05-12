variable "environment" {
  description = "Environment for tagging and naming (e.g., staging, production)"
  type        = string
  default     = "staging"
}

variable "bucket_name" {
  description = "Name of the S3 bucket that already contains environment details"
  type        = string
}

variable "bucket_arn" {
  description = "ARN of the S3 bucket"
  type        = string
}