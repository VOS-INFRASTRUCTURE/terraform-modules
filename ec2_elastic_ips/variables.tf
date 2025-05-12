variable "eip_name" {
  description = "Name tag for the Elastic IP"
  type        = string
}

variable "env" {
  description = "Environment for tagging and naming (e.g., staging, production)"
  type        = string
}

variable "project_id" {
  description = "Project ID where all project resources exists"
}
