################################################################################
# Secrets Manager VPC Interface Endpoint for Private Access
#
# Purpose: Allows EC2 instances in private subnets to access AWS Secrets Manager
#          directly without NAT Gateway or internet access.
#
# Use case: EC2 retrieves MySQL passwords from Secrets Manager during startup
#
# How it works:
# - Interface Endpoint: Creates ENI in subnet with private DNS
# - Traffic stays within AWS network (no internet gateway/NAT)
# - EC2 uses private endpoint to call secretsmanager:GetSecretValue
# - Reduces NAT Gateway costs
# - Improves security (no public IP/internet exposure)
#
# Cost comparison (per month):
# - NAT Gateway: ~$32.40 + data transfer
# - Secrets Manager Interface Endpoint: ~$7.20 + minimal data transfer
# - Savings: ~$25/month (if used with S3 Gateway Endpoint for backups)
#
# Note: This file is self-contained and discovers VPC/subnet information
#       from the EC2 instance created in main.tf
################################################################################

################################################################################
# Variable - Toggle for Secrets Manager Endpoint Creation
################################################################################

variable "enable_secretsmanager_endpoint" {
  description = "Enable Secrets Manager VPC Interface Endpoint for private access without NAT Gateway (saves ~$25/month but costs ~$7.20/month for the endpoint)"
  type        = bool
  default     = false
}


################################################################################
# Locals
################################################################################

locals {
  # Secrets Manager service name for the current region
  secretsmanager_service_name = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"

  # VPC ID from subnet
  secretsmanager_vpc_id = var.enable_secretsmanager_endpoint ? data.aws_subnet.mysql_subnet[0].vpc_id : ""

  # Subnet ID where endpoint ENI will be created (same as EC2)
  secretsmanager_subnet_ids = var.enable_secretsmanager_endpoint ? [var.subnet_id] : []

  # Security group IDs - Use same as EC2 instance
  # Note: The EC2 security group must allow outbound HTTPS (443)
  # This is typically already allowed with standard "allow all outbound" rules
  secretsmanager_sg_ids = [aws_security_group.ssm_endpoints_sg[0].id]
}

################################################################################
# Secrets Manager VPC Interface Endpoint
#
# Note: Uses the same security groups as the EC2 instance
# Requirement: EC2 security group must allow outbound HTTPS (443)
#
# Key Difference from S3 Gateway Endpoint:
# ========================================
# Interface Endpoints do NOT support endpoint policies (no 'policy' parameter).
# Access control is handled through:
# 1. IAM policies on the EC2 instance role (already configured in ec2_iam_role.tf)
# 2. Security groups (network-level control)
# 3. Private DNS (automatic routing to the endpoint)
#
# Gateway Endpoints (S3, DynamoDB) DO support endpoint policies to restrict
# which resources can be accessed via the endpoint (see s3_bucket_endpoint.tf).
################################################################################
resource "aws_security_group" "secretsmanager_sg" {
  count       = var.enable_secretsmanager_endpoint ? 1 : 0

  name        = "${var.env}-${var.project_id}-secretsmanager-sg"
  description = "SG for Secrets Manager VPC endpoint"
  vpc_id      = local.ssm_vpc_id

  # Inbound HTTPS from EC2
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups            = var.security_group_ids # EC2 SGs
    description     = "Allow EC2 instances to access Secrets Manager"
  }

  # Egress: within VPC (stateful return traffic)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vpc_cidr_block] # only allow within VPC
  }
}


resource "aws_vpc_endpoint" "secretsmanager" {
  count               = var.enable_secretsmanager_endpoint ? 1 : 0
  vpc_id              = local.secretsmanager_vpc_id
  service_name        = local.secretsmanager_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.secretsmanager_subnet_ids
  security_group_ids  = local.secretsmanager_sg_ids

  # Enable private DNS so EC2 can use standard AWS Secrets Manager endpoints
  # Without this, you'd need to use endpoint-specific DNS names
  private_dns_enabled = true

  tags = {
    Name        = "${var.env}-${var.project_id}-${var.base_name}-secretsmanager-endpoint"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "SecretsManager-VPC-Endpoint"
  }
}

################################################################################
# Output
################################################################################

output "secretsmanager_endpoint" {
  description = "Secrets Manager VPC Interface Endpoint configuration and identifiers"
  value = {
    # Toggle status
    enabled = var.enable_secretsmanager_endpoint

    # Endpoint details (present only when enabled)
    endpoint_id   = var.enable_secretsmanager_endpoint ? aws_vpc_endpoint.secretsmanager[0].id : null
    endpoint_arn  = var.enable_secretsmanager_endpoint ? aws_vpc_endpoint.secretsmanager[0].arn : null
    service_name  = local.secretsmanager_service_name
    endpoint_type = "Interface"

    # Network configuration
    vpc_id                = local.secretsmanager_vpc_id
    subnet_ids            = local.secretsmanager_subnet_ids
    security_group_ids    = local.secretsmanager_sg_ids
    private_dns_enabled   = true

    # DNS names (private DNS automatically resolves secretsmanager.REGION.amazonaws.com)
    dns_entries = var.enable_secretsmanager_endpoint ? aws_vpc_endpoint.secretsmanager[0].dns_entry : []

    # Cost estimate
    monthly_cost_estimate = var.enable_secretsmanager_endpoint ? "~$7.20 USD (Interface endpoint fee) + minimal data transfer" : "$0 (endpoint disabled, uses NAT Gateway or public internet)"
  }
}

