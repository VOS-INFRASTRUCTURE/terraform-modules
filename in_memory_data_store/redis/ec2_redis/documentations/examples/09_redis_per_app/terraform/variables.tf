variable "env" {
  description = "Environment name (e.g. staging, production)"
  type        = string
}

variable "project_id" {
  description = "Short identifier used in resource names and tags"
  type        = string
}

variable "vpc_id" {
  description = "VPC where the Redis host will be deployed"
  type        = string
}

variable "private_subnet_id" {
  description = "Private subnet for the Redis EC2 host"
  type        = string
}

variable "app1_security_group_id" {
  description = "Security group of App 1 compute resources (ECS tasks, EC2, Lambda, etc.)"
  type        = string
}

variable "app2_security_group_id" {
  description = "Security group of App 2 compute resources"
  type        = string
}
