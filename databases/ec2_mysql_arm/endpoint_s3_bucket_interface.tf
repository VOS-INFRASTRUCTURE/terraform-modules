################################################################################
# S3 Interface VPC Endpoint for Private S3 Access (No NAT Gateway Required)
#
# Purpose: Allows EC2 instances in private subnets to access S3 directly
#          without NAT Gateway or internet access.
#
# ⚠️ IMPORTANT AWS LIMITATION:
# AWS requires a Gateway endpoint to exist in the VPC before you can enable
# private DNS on an Interface endpoint. This module does NOT enable private DNS
# by default to avoid this dependency.
#
# Without private DNS enabled:
# - Standard S3 DNS (s3.region.amazonaws.com) will NOT resolve to this endpoint
# - You must use endpoint-specific DNS names (see output dns_entries)
# - Example: bucket.vpce-xxxxx.s3.region.vpce.amazonaws.com
#
# To enable private DNS (optional):
# 1. Create a Gateway endpoint for S3 in your VPC first
# 2. Then set private_dns_enabled = true in the resource below
# 3. After that, s3.region.amazonaws.com will resolve to the Interface endpoint
#
# Why Interface (not Gateway):
# - Works even when security groups block internet access
# - No dependency on NAT Gateway or route tables
# - Provides ENI with private IP in your subnet
# - Better for fully isolated architectures
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
# Locals
################################################################################

locals {
  # S3 service name for the current region
  s3_service_name = "com.amazonaws.${data.aws_region.current.name}.s3"

  # Determine if we should create the S3 endpoint (controlled by variable)
  should_create_endpoint = var.enable_s3_endpoint

  # VPC ID from subnet
  vpc_id = local.should_create_endpoint ? data.aws_subnet.mysql_subnet.vpc_id : ""

  # Subnet IDs where endpoint ENI will be created (same as EC2)
  subnet_ids = local.should_create_endpoint ? [var.subnet_id] : []

  # Security group IDs - Use same as EC2 instance
  # Note: The EC2 security group must allow outbound HTTPS (443)
  # This is typically already allowed with standard "allow all outbound" rules
  s3_sg_ids = [aws_security_group.endpoints_sg.id]
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

resource "aws_vpc_endpoint" "s3_interface" {
  count               = local.should_create_endpoint ? 1 : 0
  vpc_id              = local.vpc_id
  service_name        = local.s3_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.subnet_ids
  security_group_ids  = local.s3_sg_ids

  # NOTE: private_dns_enabled is NOT set here (defaults to false)
  # AWS requires a Gateway endpoint to exist before enabling private DNS on Interface endpoints
  # Without private DNS:
  # - You can still access S3 using the endpoint-specific DNS names
  # - Endpoint DNS format: bucket.vpce-xxxxx.s3.region.vpce.amazonaws.com
  # - Or create a Gateway endpoint first, then set private_dns_enabled = true
  #
  # To use standard S3 DNS (s3.region.amazonaws.com), you have two options:
  # 1. Create a Gateway endpoint first, then enable private DNS here
  # 2. Use the endpoint-specific DNS names provided in the output

  depends_on = [aws_vpc_endpoint.s3_gateway]

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

output "s3_interface_endpoint" {
  description = "S3 Interface VPC Endpoint configuration and identifiers"
  value = {
    # Toggle status
    enabled = local.should_create_endpoint

    # Endpoint details (present only when enabled)
    endpoint_id   = local.should_create_endpoint ? aws_vpc_endpoint.s3_interface[0].id : null
    endpoint_arn  = local.should_create_endpoint ? aws_vpc_endpoint.s3_interface[0].arn : null
    service_name  = local.s3_service_name
    endpoint_type = "Interface"

    # Network configuration
    vpc_id                = local.vpc_id
    subnet_ids            = local.subnet_ids
    security_group_ids    = local.s3_sg_ids
    private_dns_enabled   = false  # AWS requires Gateway endpoint first to enable private DNS

    # DNS entries (use these endpoint-specific DNS names to access S3)
    dns_entries = local.should_create_endpoint ? aws_vpc_endpoint.s3_interface[0].dns_entry : []

    # Usage note
    usage_note = "Without private DNS, use endpoint-specific DNS names from dns_entries above, or create a Gateway endpoint first to enable private DNS"

    # Cost estimate
    monthly_cost_estimate = local.should_create_endpoint ? "~$7.20 USD (Interface endpoint fee) + FREE data transfer (same region)" : "$0 (endpoint disabled, requires NAT Gateway or public internet for S3 access)"
  }
}
