################################################################################
# REQUIRED VARIABLES
################################################################################

variable "env" {
  description = "Environment name for resource tagging and naming (e.g., 'staging', 'production', 'dev')"
  type        = string
  validation {
    condition     = length(var.env) > 0
    error_message = "Environment name cannot be empty."
  }
}

variable "project_id" {
  description = "Project identifier for resource organization and tagging (e.g., 'myapp', 'cerpac', 'backend-api')"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

################################################################################
# NETWORK CONFIGURATION
################################################################################

variable "subnet_ids" {
  description = <<-EOT
    List of subnet IDs where the SSM Incidents VPC Interface Endpoint will be created.

    Requirements:
    - At least 1 subnet required (multiple subnets for high availability recommended)
    - Subnets must be private (recommended) for security
    - All subnets must be in the same VPC
    - For HA: Provide subnets in different availability zones

    Example:
    subnet_ids = ["subnet-abc123", "subnet-def456"]

    Cost Impact:
    - 1 subnet: ~$7.20/month
    - Multiple subnets: cost multiplied by number of subnets (for HA)
  EOT
  type        = list(string)
  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet ID must be provided in 'subnet_ids'."
  }
}

################################################################################
# SECURITY CONFIGURATION
################################################################################

variable "resources_security_group_ids" {
  description = <<-EOT
    List of security group IDs that should be allowed to access the SSM Incidents endpoint.

    Purpose:
    - These are the security groups attached to your EC2 instances,
      Lambda functions, ECS tasks, or any compute resource that needs
      to call the Incident Manager Incidents API
    - Endpoint will allow inbound HTTPS (443) from these security groups
    - Resources using these security groups must have outbound HTTPS (443) enabled

    Example:
    resources_security_group_ids = ["sg-ec2instance123", "sg-lambda456"]

    Typical Use Cases:
    - Lambda functions that create incidents on alarms
    - EC2 instances running automation that starts/updates incidents
    - ECS tasks that manage incident timeline events or response plans
  EOT
  type        = list(string)
  validation {
    condition     = length(var.resources_security_group_ids) > 0
    error_message = "At least one security group ID must be provided in 'resources_security_group_ids'."
  }
}

################################################################################
# OPTIONAL FEATURE FLAGS
################################################################################

variable "enable_ssm_incidents_endpoint" {
  description = <<-EOT
    Enable SSM Incidents (Incident Manager) VPC Interface Endpoint for private
    access without NAT Gateway.

    When enabled:
    - Creates 1 VPC Interface Endpoint for SSM Incidents (ssm-incidents)
    - Allows Incident Manager Incidents API calls from private subnets without internet
    - Eliminates need for NAT Gateway for ssm-incidents traffic (saves ~$25/month)
    - All ssm-incidents API calls stay within AWS private network

    AWS Service: AWS Systems Manager Incident Manager (Incidents)
    Service name: com.amazonaws.{region}.ssm-incidents

    Cost: ~$7.20/month per AZ (Interface Endpoint fee) + $0.01/GB data transfer

    Default: false (disabled - opt-in to avoid unexpected costs)
  EOT
  type        = bool
  default     = false
}

