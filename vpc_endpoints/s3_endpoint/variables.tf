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
    List of subnet IDs for S3 Interface VPC Endpoint (if enabled).
    Note: Only needed if enable_s3_interface_endpoint = true
    Gateway endpoint doesn't use subnets (works via route tables)
    Requirements:
    - At least 1 subnet required for Interface endpoint
    - Multiple subnets recommended for high availability
    - All subnets must be in the same VPC
    - For HA: Provide subnets in different availability zones
    Example:
    subnet_ids = ["subnet-abc123", "subnet-def456"]
    Cost Impact (Interface endpoint only):
    - 1 subnet: ~$7.20/month
    - 2 subnets (multi-AZ): ~$14.40/month
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
    List of security group IDs for resources accessing S3 via VPC endpoints.
    Note: Only needed if enable_s3_interface_endpoint = true
    Gateway endpoint doesn't use security groups
    Purpose:
    - Security groups of EC2 instances, Lambda, or ECS tasks accessing S3
    - Interface endpoint will allow inbound HTTPS (443) from these SGs
    - Required for resources to access S3 via Interface endpoint
    Requirements:
    - At least 1 security group ID required for Interface endpoint
    - Security groups must be in the same VPC
    - Resources must have outbound HTTPS (443) enabled
    Example:
    resources_security_group_ids = ["sg-ec2-app", "sg-lambda", "sg-ecs-tasks"]
    Typical Use Cases:
    - EC2 instances uploading backups to S3
    - Lambda functions processing S3 files
    - ECS tasks reading/writing to S3
  EOT
  type        = list(string)
  validation {
    condition     = length(var.resources_security_group_ids) > 0
    error_message = "At least one security group ID must be provided in 'resources_security_group_ids'."
  }
}
################################################################################
# S3 BUCKET CONFIGURATION
################################################################################
variable "s3_bucket_arns" {
  description = <<-EOT
    List of S3 bucket ARNs to restrict endpoint access (security best practice).
    Purpose:
    - Restricts which S3 buckets can be accessed via the VPC endpoint
    - Prevents unauthorized access to other S3 buckets
    - Applies to Gateway endpoint policy (Interface doesn't support policies)
    How it works:
    - Gateway endpoint: Policy enforced at route level
    - Interface endpoint: Use IAM policies on EC2 role instead
    Requirements:
    - At least 1 S3 bucket ARN required
    - Buckets can be in same or different AWS accounts
    - ARN format: arn:aws:s3:::bucket-name
    Example:
    s3_bucket_arns = [
      "arn:aws:s3:::my-backups-bucket",
      "arn:aws:s3:::my-logs-bucket",
      "arn:aws:s3:::my-data-bucket"
    ]
    Security Note:
    - Restricting bucket access prevents accidental data exfiltration
    - Follow principle of least privilege
    - Review bucket list periodically
  EOT
  type        = list(string)
  validation {
    condition     = length(var.s3_bucket_arns) > 0
    error_message = "At least one S3 bucket ARN must be provided in 's3_bucket_arns'."
  }
}
################################################################################
# OPTIONAL FEATURE FLAGS
################################################################################
variable "enable_s3_gateway_endpoint" {
  description = <<-EOT
    Enable S3 Gateway VPC Endpoint for FREE private S3 access.
    Recommended: TRUE (default choice for most use cases)
    When enabled:
    - Creates Gateway endpoint (adds route to route tables)
    - FREE - No hourly charges, no data transfer fees
    - Works for EC2, Lambda (with VPC), ECS in private subnets
    - Supports endpoint policies for security
    Cost:
    - Gateway endpoint: FREE (no charges)
    - NAT Gateway avoided: Saves ~$32.40/month
    How it works:
    - Adds S3 prefix list route to your route tables
    - Traffic to S3 bypasses NAT/IGW
    - Stays within AWS network
    Set to false if:
    - Route tables are managed externally
    - Need Interface endpoint instead for specific architecture
  EOT
  type        = bool
  default     = true
}
variable "enable_s3_interface_endpoint" {
  description = <<-EOT
    Enable S3 Interface VPC Endpoint for private S3 access.
    Use when: Gateway endpoint doesn't meet your needs
    When enabled:
    - Creates Interface endpoint (ENI in your subnets)
    - Cost: ~$7.20/month per AZ
    - Provides private DNS (s3.region.amazonaws.com)
    - Works in fully isolated subnets
    - Required if Gateway endpoint can't be used
    Cost:
    - 1 AZ: ~$7.20/month
    - 2 AZ (HA): ~$14.40/month
    - NAT Gateway avoided: Saves ~$25/month
    When to use Interface instead of Gateway:
    - Cannot modify route tables
    - Need private DNS for compatibility
    - Fully isolated architecture (zero internet)
    - Security requires ENI-based access
    Note: Requires Gateway endpoint to exist for private DNS
    Set to false if:
    - Gateway endpoint is sufficient
    - Want to avoid endpoint hourly charges
  EOT
  type        = bool
  default     = false
}
