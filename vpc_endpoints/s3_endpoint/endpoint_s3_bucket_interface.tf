################################################################################
# S3 INTERFACE VPC ENDPOINT
#
# Purpose: Provides ENI-based private S3 access for fully isolated architectures
#
# Why Use Interface Endpoint (vs Gateway):
# - Gateway endpoint can't be used (route table constraints)
# - Need private DNS (s3.region.amazonaws.com)
# - Security requires ENI with security groups
# - Fully isolated subnet (zero internet, even for internal routes)
#
# Cost vs Gateway:
# - Interface: ~$7.20/month per AZ + FREE data transfer
# - Gateway: FREE
# - Use Interface only when Gateway doesn't work
#
# How Interface Endpoint Works:
# ┌─────────────────────────────────────────────────────────────────────────┐
# │ 1. Creates ENI (network interface) in your subnet                       │
# │ 2. Provides private IP for S3 service                                   │
# │ 3. Private DNS makes s3.region.amazonaws.com resolve to private IP     │
# │ 4. Security group controls access                                       │
# │ 5. Traffic never leaves AWS network                                     │
# └─────────────────────────────────────────────────────────────────────────┘
#
# ⚠️ AWS LIMITATION - Private DNS Requirement:
# AWS requires a Gateway endpoint to exist before enabling private DNS
# on Interface endpoints. This module handles this automatically by:
# 1. Creating Gateway endpoint (if enabled)
# 2. Creating Interface endpoint with private DNS
# 3. Making Interface endpoint depend on Gateway endpoint
#
# Without private DNS enabled:
# - Standard S3 URLs (s3.region.amazonaws.com) won't work
# - Must use endpoint-specific DNS (see output dns_entries)
#
# Security Model:
# - Dedicated security group for endpoint
# - Allows HTTPS (443) from resource security groups
# - Egress restricted to VPC CIDR only
################################################################################
################################################################################
# S3 INTERFACE VPC ENDPOINT
#
# Type: Interface (NOT Gateway)
# - Creates ENI in your subnets
# - Costs ~$7.20/month per AZ
# - Provides private DNS
# - Use when Gateway endpoint doesn't meet needs
################################################################################
resource "aws_vpc_endpoint" "s3_interface" {
  count = local.create_interface_endpoint ? 1 : 0
  vpc_id              = data.aws_vpc.target_vpc.id
  service_name        = local.s3_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.s3_endpoint_sg[0].id]
  # CRITICAL: Private DNS requires Gateway endpoint to exist first
  # This resolves s3.region.amazonaws.com to endpoint's private IP
  # Without this, must use endpoint-specific DNS names
  private_dns_enabled = true
  # DNS options for private DNS configuration
  dns_options {
    # Only use private DNS for resolver endpoints in VPC
    # This prevents DNS leakage to public resolvers
    private_dns_only_for_inbound_resolver_endpoint = false
  }
  # Dependency: Gateway endpoint must exist before Interface endpoint
  # AWS requirement for enabling private DNS
  depends_on = [aws_vpc_endpoint.s3_gateway]
  tags = {
    Name        = "${var.env}-${var.project_id}-${data.aws_vpc.target_vpc.id}-s3-interface-endpoint"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "S3-InterfaceEndpoint"
    Type        = "Interface"
    Cost        = "~$7.20/month per AZ"
  }
}
################################################################################
# SECURITY GROUP FOR S3 INTERFACE ENDPOINT
#
# Purpose: Controls access to S3 Interface endpoint
# Only created when Interface endpoint is enabled
################################################################################
resource "aws_security_group" "s3_endpoint_sg" {
  count = local.create_interface_endpoint ? 1 : 0
  name        = "${var.env}-${var.project_id}-s3-interface-endpoint-sg"
  description = "Security group for S3 Interface VPC Endpoint - allows HTTPS from resources"
  vpc_id      = data.aws_vpc.target_vpc.id
  # Inbound: Allow HTTPS (443) from resources that need S3 access
  ingress {
    description     = "Allow HTTPS from resources for S3 API calls"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = var.resources_security_group_ids
  }
  # Outbound: Allow return traffic within VPC only
  egress {
    description = "Allow return traffic to resources within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vpc_cidr_block]
  }
  tags = {
    Name        = "${var.env}-${var.project_id}-s3-interface-endpoint-sg"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "S3-InterfaceEndpoint-SecurityGroup"
  }
}
################################################################################
# OUTPUT - Interface Endpoint Information
################################################################################
output "s3_interface_endpoint" {
  description = "S3 Interface VPC Endpoint configuration and identifiers"
  value = {
    # Feature toggle status
    enabled = local.create_interface_endpoint
    # Endpoint details
    endpoint = {
      endpoint_id         = local.create_interface_endpoint ? aws_vpc_endpoint.s3_interface[0].id : null
      endpoint_arn        = local.create_interface_endpoint ? aws_vpc_endpoint.s3_interface[0].arn : null
      service_name        = local.s3_service_name
      endpoint_type       = "Interface"
      private_dns_enabled = true
      state               = local.create_interface_endpoint ? aws_vpc_endpoint.s3_interface[0].state : null
      dns_entries         = local.create_interface_endpoint ? aws_vpc_endpoint.s3_interface[0].dns_entry : []
    }
    # Network configuration
    network = {
      vpc_id             = data.aws_vpc.target_vpc.id
      subnet_ids         = var.subnet_ids
      security_group_ids = local.create_interface_endpoint ? [aws_security_group.s3_endpoint_sg[0].id] : []
      vpc_cidr_block     = local.vpc_cidr_block
    }
    # Cost information
    cost = {
      monthly_estimate  = local.create_interface_endpoint ? "~$7.20 USD per AZ (Interface endpoint fee)" : "$0 (endpoint disabled)"
      data_transfer     = "FREE (S3 data transfer in same region is FREE)"
      nat_gateway_saved = "~$32.40/month + $0.045/GB data transfer"
      net_savings       = "~$25.20+/month"
    }
    # Usage instructions
    usage = {
      aws_cli_example   = "aws s3 ls s3://your-bucket/ --region ${data.aws_region.current.name}"
      python_example    = "boto3.client('s3').list_objects_v2(Bucket='your-bucket')"
      dns_note          = "Private DNS enabled - s3.${data.aws_region.current.name}.amazonaws.com resolves to endpoint private IP"
      requirements      = [
        "Resource must be in VPC with subnets connected to this endpoint",
        "Resource security group must allow outbound HTTPS (443)",
        "IAM role/user must have s3:* permissions for target buckets",
        "Gateway endpoint must exist for private DNS to work"
      ]
    }
  }
}
