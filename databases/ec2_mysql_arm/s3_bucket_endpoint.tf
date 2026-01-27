################################################################################
# S3 Interface VPC Endpoint for Private S3 Access (No NAT Gateway Required)
#
# Purpose: Allows EC2 instances in private subnets to access S3 directly
#          without NAT Gateway or internet access.
#
# Why Interface (not Gateway):
# - Provides private DNS (s3.region.amazonaws.com resolves to private IP)
# - Works with AWS CLI/SDK without any configuration changes
# - No dependency on NAT Gateway or internet access
# - Works even when security groups block internet access
#
# How it works:
# - Creates ENI (network interface) in your subnet with private IP
# - Private DNS enabled: S3 DNS names resolve to endpoint's private IP
# - Traffic stays within AWS network (no internet gateway/NAT)
# - Reduces NAT Gateway costs (~$25/month net savings)
#
# Cost:
# - Interface endpoint: ~$7.20/month per AZ
# - NAT Gateway avoided: ~$32.40/month
# - Net savings: ~$25/month + better security
#
# When to enable:
# - EC2 in private subnet WITHOUT NAT Gateway
# - EC2 in private subnet with NAT BUT internet access is blocked
# - Want fully isolated private architecture (zero internet exposure)
# - Need `aws s3 ls/cp` to work without special configuration
#
# Note: This file is self-contained and discovers VPC/subnet information
#       from the EC2 instance created in main.tf
################################################################################

################################################################################
# Variable - Toggle for S3 Endpoint Creation
################################################################################

variable "enable_s3_endpoint" {
  description = "Enable S3 Interface VPC Endpoint for private S3 access without NAT Gateway (~$7.20/month but saves ~$25/month vs NAT, enables fully private architecture)"
  type        = bool
  default     = false
}

################################################################################
# Data Sources - Auto-discover network configuration from EC2 instance
################################################################################

# Get subnet details from the EC2 instance
data "aws_subnet" "mysql_subnet" {
  count = var.enable_s3_endpoint ? 1 : 0
  id    = var.subnet_id
}


################################################################################
# Locals
################################################################################

locals {
  # S3 service name for the current region
  s3_service_name = "com.amazonaws.${data.aws_region.current.name}.s3"

  # Determine if we should create the S3 endpoint (controlled by variable)
  should_create_endpoint = var.enable_s3_endpoint

  # VPC ID from subnet
  vpc_id = local.should_create_endpoint ? data.aws_subnet.mysql_subnet[0].vpc_id : ""

  # Subnet IDs where endpoint ENI will be created (same as EC2)
  subnet_ids = local.should_create_endpoint ? [var.subnet_id] : []

  # Security group IDs - Use same as EC2 instance
  # Note: The EC2 security group must allow outbound HTTPS (443)
  # This is typically already allowed with standard "allow all outbound" rules
  s3_sg_ids = [aws_security_group.ssm_endpoints_sg[0].id]
}


################################################################################
# S3 Interface VPC Endpoint
#
# Note: Uses the same security groups as the EC2 instance
# Requirement: EC2 security group must allow outbound HTTPS (443)
#
# Key Difference from Gateway Endpoint:
# - Interface endpoints do NOT support endpoint policies
# - Access control is handled through IAM policies on the EC2 instance role
# - Provides private DNS (s3.region.amazonaws.com resolves to private IP)
# - Creates ENI in subnet (not route table modification)
################################################################################

resource "aws_vpc_endpoint" "s3" {
  count               = local.should_create_endpoint ? 1 : 0
  vpc_id              = local.vpc_id
  service_name        = local.s3_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.subnet_ids
  security_group_ids  = local.s3_sg_ids

  # CRITICAL: Private DNS must be enabled for normal CLI/SDK access
  # This makes s3.region.amazonaws.com resolve to the endpoint's private IP
  private_dns_enabled = true

  tags = {
    Name        = "${var.env}-${var.project_id}-${var.base_name}-s3-endpoint"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "S3-InterfaceEndpoint-MySQL-Backups"
  }
}

################################################################################
# Output
################################################################################

output "s3_endpoint" {
  description = "S3 Interface VPC Endpoint configuration and identifiers"
  value = {
    # Toggle status
    enabled = local.should_create_endpoint

    # Endpoint details (present only when enabled)
    endpoint_id   = local.should_create_endpoint ? aws_vpc_endpoint.s3[0].id : null
    endpoint_arn  = local.should_create_endpoint ? aws_vpc_endpoint.s3[0].arn : null
    service_name  = local.s3_service_name
    endpoint_type = "Interface"

    # Network configuration
    vpc_id                = local.vpc_id
    subnet_ids            = local.subnet_ids
    security_group_ids    = local.s3_sg_ids
    private_dns_enabled   = true

    # DNS entries (private DNS automatically resolves s3.region.amazonaws.com)
    dns_entries = local.should_create_endpoint ? aws_vpc_endpoint.s3[0].dns_entry : []

    # Cost estimate
    monthly_cost_estimate = local.should_create_endpoint ? "~$7.20 USD (Interface endpoint fee) + FREE data transfer (same region)" : "$0 (endpoint disabled, requires NAT Gateway or public internet for S3 access)"
  }
}
