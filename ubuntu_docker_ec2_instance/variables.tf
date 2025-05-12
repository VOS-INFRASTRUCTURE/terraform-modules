variable "env" {
  description = "Environment for tagging and naming (e.g., staging, production)"
  type        = string
}

variable "project_id" {
  description = "Project ID where all project resources exists"
}

variable "ami_id" {
  description = "The AMI ID to use for the instance"
  type        = string
}

variable "instance_type" {
  description = "The type of instance to launch"
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet where the instance will be launched"
  type        = string
}

variable "security_group_ids" {
  description = "A list of security group IDs to assign to the instance"
  type        = list(string)
}

variable "key_name" {
  description = "The key pair name to allow SSH access to the instance"
  type        = string
}

variable "storage_size" {
  description = "The size of the root volume in GB"
  type        = number
}

variable "storage_type" {
  description = "The type of storage to use for the root volume (e.g., gp2, gp3)"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to the instance"
  type        = map(string)
  default     = {}
}

variable "base_name" {
  description = "The name tag for the instance without any prefix"
  type        = string
}
