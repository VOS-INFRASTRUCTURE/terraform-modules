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
    List of subnet IDs where SSM Contacts VPC Interface Endpoint will be created.

    Requirements:
    - At least 1 subnet required (multiple subnets for high availability recommended)
    - Subnets can be private or public (private recommended for security)
    - All subnets must be in the same VPC
    - For HA: Provide subnets in different availability zones

    Example:
    subnet_ids = ["subnet-abc123", "subnet-def456"]

    Cost Impact:
    - 1 subnet: Standard endpoint cost (~$7.20/month)
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
    List of security group IDs that should be allowed to access the SSM Contacts endpoint.

    Purpose:
    - These are typically the security groups attached to your EC2 instances,
      Lambda functions, ECS tasks, or any compute resource using Incident Manager
    - Endpoint will allow inbound HTTPS (443) from these security groups
    - Required for resources to communicate with SSM Contacts via VPC endpoint

    Requirements:
    - At least 1 security group ID required
    - Security groups must be in the same VPC as the subnets
    - Resources using these security groups must have outbound HTTPS (443) enabled

    Example:
    resources_security_group_ids = ["sg-ec2instance123", "sg-lambda456"]

    Typical Use Cases:
    - EC2 instances triggering incident response contacts
    - Lambda functions sending alerts via Incident Manager
    - Automation scripts that create or acknowledge contacts/engagements
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

variable "enable_ssm_contacts_endpoint" {
  description = <<-EOT
    Enable SSM Contacts (Incident Manager) VPC Interface Endpoint for private
    access without NAT Gateway.

    When enabled:
    - Creates 1 VPC Interface Endpoint for SSM Contacts (ssm-contacts)
    - Allows Incident Manager API calls from private subnets without internet
    - Eliminates need for NAT Gateway for ssm-contacts traffic (saves ~$25/month)
    - All ssm-contacts API calls stay within AWS private network

    AWS Service: AWS Systems Manager Incident Manager (Contacts)
    Endpoint:    com.amazonaws.{region}.ssm-contacts

    Cost Breakdown:
    - 1 endpoint × $7.20/month = ~$7.20/month (single AZ)
    - NAT Gateway alternative: ~$32.40/month + data transfer
    - Net savings: ~$25.20/month + improved security

    Security Benefits:
    - No internet gateway or NAT required
    - Incident Manager API calls never traverse public internet
    - All traffic stays within AWS network
    - Full audit trail via CloudTrail

    Set to false if:
    - You already have NAT Gateway serving this traffic
    - EC2 instances have public IPs
    - Very infrequent Incident Manager API usage
  EOT
  type        = bool
  default     = false
}

