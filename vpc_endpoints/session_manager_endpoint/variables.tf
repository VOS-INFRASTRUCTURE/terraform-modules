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
    List of subnet IDs where Session Manager VPC Interface Endpoints will be created.

    Requirements:
    - At least 1 subnet required (multiple subnets for high availability recommended)
    - Subnets can be private or public (private recommended for security)
    - All subnets must be in the same VPC
    - For HA: Provide subnets in different availability zones

    Example:
    subnet_ids = ["subnet-abc123", "subnet-def456"]

    Cost Impact:
    - 1 subnet: Standard endpoint cost (~$7.20/month per endpoint)
    - Multiple subnets: Cost multiplied by number of subnets (for HA)
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
    List of security group IDs that should be allowed to access Session Manager endpoints.

    Purpose:
    - These are typically the security groups attached to your EC2 instances
    - Endpoints will allow inbound HTTPS (443) from these security groups
    - Required for EC2 instances to communicate with Session Manager

    Requirements:
    - At least 1 security group ID required
    - Security groups must be in the same VPC as the subnets
    - EC2 instances using these security groups must have outbound HTTPS (443) enabled

    Example:
    resources_security_group_ids = ["sg-ec2instance123", "sg-database456"]

    Typical Use Case:
    - EC2 instance security group
    - RDS database security group (if using Session Manager for DB access)
    - Any compute resource requiring SSH-less access
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

variable "enable_session_manager_endpoints" {
  description = <<-EOT
    Enable Session Manager VPC Interface Endpoints for SSH-less access without NAT Gateway.

    When enabled:
    - Creates 3 VPC Interface Endpoints (ssm, ssmmessages, ec2messages)
    - Allows Session Manager access from private subnets without internet
    - Eliminates need for NAT Gateway (saves ~$10/month)

    Cost Breakdown:
    - 3 endpoints × $7.20/month = ~$21.60/month
    - NAT Gateway alternative: ~$32.40/month + data transfer
    - Net savings: ~$10/month + improved security

    Security Benefits:
    - No internet gateway or NAT required
    - All traffic stays within AWS network
    - No SSH keys to manage
    - Audit trail via CloudTrail

    Set to false if:
    - You already have NAT Gateway
    - EC2 instances have public IPs
    - Cost optimization not needed
  EOT
  type        = bool
  default     = false
}

