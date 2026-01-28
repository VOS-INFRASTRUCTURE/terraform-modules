################################################################################
# AWS SYSTEMS MANAGER (SSM) SESSION MANAGER VPC ENDPOINTS
#
# Purpose: Enables Session Manager for SSH-less access to EC2 instances in
#          private subnets without NAT Gateway or internet access.
#
# ⚠️ CRITICAL: ALL THREE endpoints are MANDATORY for Session Manager to work!
# Missing even ONE endpoint will break Session Manager completely.
#
# Required Endpoints:
# 1. com.amazonaws.{region}.ssm          - Systems Manager API
# 2. com.amazonaws.{region}.ssmmessages  - Session Manager messages
# 3. com.amazonaws.{region}.ec2messages  - EC2 instance communication
#
# How Session Manager Works:
# ┌─────────────────────────────────────────────────────────────────────────┐
# │ 1. User connects via AWS Console or CLI                                 │
# │ 2. Request goes to Session Manager API (ssm endpoint)                   │
# │ 3. Session Manager establishes tunnel via ssmmessages endpoint          │
# │ 4. EC2 instance communicates back via ec2messages endpoint              │
# │ 5. Secure session established - no SSH keys or open ports needed!       │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Network Flow:
#   EC2 (Private Subnet) → VPC Endpoint → Session Manager Service
#                  ↓
#   No NAT, No IGW, No Public IP needed!
#
# Cost Comparison (per month, per AZ):
# ┌────────────────────────────┬──────────┬────────────────────────┐
# │ Solution                   │ Cost     │ Notes                  │
# ├────────────────────────────┼──────────┼────────────────────────┤
# │ NAT Gateway                │ ~$32.40  │ + data transfer fees   │
# │ 3 SSM Interface Endpoints  │ ~$21.60  │ + minimal data transfer│
# │ Savings                    │ ~$10.80  │ + better security      │
# └────────────────────────────┴──────────┴────────────────────────┘
#
# Security Benefits:
# ✅ No SSH keys to manage or rotate
# ✅ No open SSH port (22) on EC2 instances
# ✅ No internet gateway or NAT required
# ✅ All traffic stays within AWS network
# ✅ Full audit trail via CloudTrail
# ✅ IAM-based access control
#
# When to Use This Module:
# ✅ EC2 instances in private subnets
# ✅ Need SSH-less access for administration
# ✅ Want to avoid NAT Gateway costs
# ✅ Security compliance requires no internet access
# ✅ Multi-account setup with centralized access
#
# When NOT to Use:
# ❌ Already have NAT Gateway (no cost benefit)
# ❌ EC2 instances have public IPs
# ❌ Need outbound internet for other services (still need NAT)
################################################################################
################################################################################
# LOCALS - Computed Values
################################################################################
locals {
  # Session Manager service names for the current region
  # These are AWS-managed service endpoints that follow a standard naming pattern
  secretsmanager_service_name         = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"

  # VPC ID discovered from provided subnet
  # Only computed when endpoints are enabled to avoid unnecessary data lookups
  secretsmanager_vpc_id = var.enable_secretsmanager_endpoint ? data.aws_subnet.any_subnet.vpc_id : ""
  # Subnet IDs where endpoint ENIs will be created
  # Same subnets as the EC2 instances that need Session Manager access
  secretsmanager_subnet_ids = var.enable_secretsmanager_endpoint ? var.subnet_ids : []
  # Security group for the VPC endpoints
  # Allows inbound HTTPS (443) from EC2 instances
  secretsmanager_sg_ids = var.enable_secretsmanager_endpoint ? [aws_security_group.endpoints_sg[0].id] : []
  # VPC CIDR block for endpoint security group egress rules
  # Restricts outbound traffic to stay within VPC only
  vpc_cidr_block = var.enable_secretsmanager_endpoint ? data.aws_vpc.target_vpc.cidr_block : ""
}
################################################################################
# VPC INTERFACE ENDPOINTS FOR SESSION MANAGER
#
# Endpoint Type: Interface (NOT Gateway)
# - Creates ENI (Elastic Network Interface) in each specified subnet
# - Provides private IP addresses within your VPC
# - Requires private DNS enabled for Session Manager to work
#
# Key Requirements:
# ✅ ALL THREE endpoints must be created together
# ✅ private_dns_enabled = true (mandatory)
# ✅ Security group must allow HTTPS (443) inbound from EC2
# ✅ EC2 security group must allow HTTPS (443) outbound
#
# Missing ANY one of these = Session Manager will NOT work!
################################################################################
# Endpoint 1: SSM (Systems Manager API)
# Purpose: Core Systems Manager service communication
# - Handles Session Manager API calls
# - Manages session lifecycle (start, stop, status)
# - Required for: aws ssm start-session commands
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
    Name        = "${var.env}-${var.project_id}-${data.aws_vpc.target_vpc.id}-secretsmanager-endpoint"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "SecretsManager-VPC-Endpoint"
  }
}

