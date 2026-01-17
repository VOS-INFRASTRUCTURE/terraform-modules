################################################################################
# Variables for IAM Access Analyzer Module
################################################################################

variable "env" {
  description = "Environment name (e.g., staging, production)"
  type        = string
}

variable "project_id" {
  description = "Project identifier for resource naming and tagging"
  type        = string
}

variable "enable_access_analyzer" {
  description = "Whether to enable IAM Access Analyzer (Security Hub IAM.21)"
  type        = bool
  default     = true
}

variable "analyzer_type" {
  description = "Type of analyzer to create: ACCOUNT (current account only) or ORGANIZATION (entire org - requires management account)"
  type        = string
  default     = "ACCOUNT"

  validation {
    condition     = contains(["ACCOUNT", "ORGANIZATION"], var.analyzer_type)
    error_message = "analyzer_type must be either ACCOUNT or ORGANIZATION"
  }
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

