################################################################################
# Variables for SSM Security Module
################################################################################

variable "env" {
  description = "Environment name (e.g., staging, production)"
  type        = string
}

variable "project_id" {
  description = "Project identifier for resource naming and tagging"
  type        = string
}

variable "enable_ssm_public_sharing_block" {
  description = "Whether to block SSM document public sharing (Security Hub SSM.7)"
  type        = bool
  default     = true
}

variable "enable_ssm_automation_logging" {
  type    = bool
  default = true
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

