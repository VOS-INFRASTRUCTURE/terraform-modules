################################################################################
# Variables for EC2 MySQL Module
################################################################################

variable "env" {
  description = "Environment for tagging and naming (e.g., staging, production)"
  type        = string
}

variable "project_id" {
  description = "Project ID where all project resources exist"
  type        = string
}

# Target SubnetIds
variable "subnet_ids" {
  description = "List of Subnet IDs where the Session Manager endpoints will be created"
  type        = list(string)

  // No default, must be provided, minimum 1 subnet
    validation {
        condition     = length(var.subnet_ids) > 0
        error_message = "At least one subnet ID must be provided in 'subnet_ids'."
    }
}


// Target Security Group IDs
variable "resources_security_group_ids" {
  description = "List of Security Group IDs to be allowed by the Session Manager endpoints"
  type        = list(string)
    // No default, must be provided, minimum 1 SG
        validation {
            condition     = length(var.resources_security_group_ids) > 0
            error_message = "At least one security group ID must be provided in 'security_group_ids'."
        }
}
