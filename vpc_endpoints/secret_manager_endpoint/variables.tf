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
    List of subnet IDs where Secrets Manager VPC Interface Endpoint will be created.
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
    List of security group IDs that should be allowed to access Secrets Manager endpoint.
    Purpose:
    - These are typically the security groups attached to your EC2 instances, Lambda functions, or ECS tasks
    - Endpoint will allow inbound HTTPS (443) from these security groups
    - Required for resources to communicate with Secrets Manager via VPC endpoint
    Requirements:
    - At least 1 security group ID required
    - Security groups must be in the same VPC as the subnets
    - Resources using these security groups must have outbound HTTPS (443) enabled
    Example:
    resources_security_group_ids = ["sg-ec2instance123", "sg-lambda456", "sg-ecs-tasks789"]
    Typical Use Cases:
    - EC2 instances fetching database credentials
    - Lambda functions accessing API keys
    - ECS tasks retrieving secrets at startup
    - RDS instances with secret rotation enabled
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
variable "enable_secretsmanager_endpoint" {
  description = <<-EOT
    Enable Secrets Manager VPC Interface Endpoint for private access without NAT Gateway.
    When enabled:
    - Creates 1 VPC Interface Endpoint for Secrets Manager
    - Allows Secrets Manager access from private subnets without internet
    - Eliminates need for NAT Gateway (saves ~$25/month)
    - All secrets API calls stay within AWS private network
    Cost Breakdown:
    - 1 endpoint × $7.20/month = ~$7.20/month (single AZ)
    - NAT Gateway alternative: ~$32.40/month + data transfer
    - Net savings: ~$25.20/month + improved security
    Security Benefits:
    - No internet gateway or NAT required
    - Secrets never traverse public internet
    - All traffic stays within AWS network
    - Full audit trail via CloudTrail
    - Private DNS for seamless integration
    Set to false if:
    - You already have NAT Gateway for other services
    - EC2 instances have public IPs
    - Very low secret access frequency
    - Cost optimization not needed
  EOT
  type        = bool
  default     = false
}
