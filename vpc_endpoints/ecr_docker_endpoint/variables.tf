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
    List of subnet IDs where ECR VPC Interface Endpoints will be created.

    Requirements:
    - At least 1 subnet required (multiple subnets for high availability recommended)
    - Should be the SAME subnets where your ECS tasks or EC2 instances run
    - All subnets must be in the same VPC
    - For HA: Provide subnets in different availability zones

    Example:
    subnet_ids = ["subnet-abc123", "subnet-def456"]

    Cost Impact:
    - Each additional subnet multiplies endpoint cost
    - 1 subnet × 3 endpoints = ~$21.60/month
    - 2 subnets × 3 endpoints = ~$43.20/month
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
    List of security group IDs attached to resources that need to pull images from ECR.

    Purpose:
    - These are the security groups attached to your ECS tasks, EC2 instances,
      Lambda container functions, or CodeBuild projects
    - Endpoint will allow inbound HTTPS (443) from these security groups
    - Resources using these security groups must also have outbound HTTPS (443) enabled

    Example:
    resources_security_group_ids = [
      "sg-ecs-task-abc123",
      "sg-ec2-instance-def456"
    ]

    Typical Use Cases:
    - ECS Fargate tasks pulling container images from ECR
    - EC2 instances with Docker daemon pulling images
    - Lambda container image functions
    - CodeBuild projects building images from ECR base images
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

variable "enable_ecr_endpoints" {
  description = <<-EOT
    Enable ECR VPC Interface Endpoints (ecr.api + ecr.dkr + s3 interface).

    When enabled, creates:
    - ecr.api endpoint: ECR control plane (auth tokens, image metadata)
    - ecr.dkr endpoint: Docker Registry protocol (image pull/push)
    - s3 interface endpoint: ECR image layer downloads from S3

    ALL THREE are required for container image pulls to work in private subnets.

    AWS Services:
    - com.amazonaws.{region}.ecr.api
    - com.amazonaws.{region}.ecr.dkr
    - com.amazonaws.{region}.s3 (Interface type)

    Cost: ~$21.60/month per AZ (3 × $7.20) + minimal data transfer ($0.01/GB)

    Default: false (disabled - opt-in to avoid unexpected costs)
  EOT
  type        = bool
  default     = false
}

variable "create_s3_endpoint" {
  description = <<-EOT
    Whether to create the S3 Interface Endpoint as part of this module.

    ECR image layers are stored in S3. Container image pulls require S3 access.
    This module creates an S3 Interface Endpoint to enable private S3 access
    for ECR layer downloads.

    Set to false if:
    - You already have an S3 Interface Endpoint in this VPC (from s3_endpoint module)
    - You want to manage the S3 endpoint separately

    ⚠️  If false AND no other S3 Interface Endpoint exists:
        - Image layer downloads WILL FAIL in private subnets
        - S3 Gateway endpoints are NOT sufficient (no private DNS)

    Default: true (create S3 endpoint alongside ECR endpoints)
  EOT
  type        = bool
  default     = true
}

