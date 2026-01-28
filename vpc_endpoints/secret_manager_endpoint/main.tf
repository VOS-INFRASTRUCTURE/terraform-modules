################################################################################
# AWS SECRETS MANAGER VPC ENDPOINT
#
# Purpose: Enables private access to AWS Secrets Manager from EC2 instances in
#          private subnets without NAT Gateway or internet access.
#
# What is Secrets Manager:
# AWS Secrets Manager helps you manage, retrieve, and rotate database credentials,
# API keys, and other secrets throughout their lifecycle.
#
# Why Use VPC Endpoint for Secrets Manager:
# ┌─────────────────────────────────────────────────────────────────────────┐
# │ 1. EC2 instance needs to fetch secrets (DB password, API keys, etc.)    │
# │ 2. Without VPC endpoint: Requires NAT Gateway or internet access        │
# │ 3. With VPC endpoint: Traffic stays private within AWS network          │
# │ 4. Secrets Manager API calls route through private VPC endpoint         │
# │ 5. More secure + cost-effective (saves NAT Gateway costs)               │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Network Flow:
#   EC2 (Private Subnet) → VPC Endpoint → Secrets Manager Service
#                  ↓
#   No NAT, No IGW, No Public IP needed!
#
# Cost Comparison (per month, per AZ):
# ┌────────────────────────────┬──────────┬────────────────────────┐
# │ Solution                   │ Cost     │ Notes                  │
# ├────────────────────────────┼──────────┼────────────────────────┤
# │ NAT Gateway                │ ~$32.40  │ + data transfer fees   │
# │ Secrets Manager Endpoint   │ ~$7.20   │ + minimal data transfer│
# │ Savings                    │ ~$25.20  │ + better security      │
# └────────────────────────────┴──────────┴────────────────────────┘
#
# Security Benefits:
# ✅ No internet gateway or NAT required
# ✅ All traffic stays within AWS network
# ✅ Secrets never traverse the public internet
# ✅ Full audit trail via CloudTrail
# ✅ Private DNS resolution for seamless integration
#
# When to Use This Module:
# ✅ EC2 instances in private subnets need to access Secrets Manager
# ✅ Applications fetch database credentials from Secrets Manager
# ✅ Want to avoid NAT Gateway costs
# ✅ Security compliance requires no internet access
# ✅ Lambda functions in VPC need secrets
#
# When NOT to Use:
# ❌ Already have NAT Gateway (no cost benefit if used for other services)
# ❌ EC2 instances have public IPs with internet gateway
# ❌ Very low secret access frequency (cost may not justify endpoint)
#
# Common Use Cases:
# - Fetching RDS/database credentials at application startup
# - Retrieving API keys for third-party integrations
# - Accessing encryption keys
# - Rotating secrets automatically
################################################################################
################################################################################
# LOCALS - Computed Values
################################################################################
locals {
  # Secrets Manager service name for the current region
  # AWS-managed service endpoint following standard naming pattern
  secretsmanager_service_name = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  # VPC ID discovered from provided subnet
  # Only computed when endpoint is enabled to avoid unnecessary data lookups
  secretsmanager_vpc_id = var.enable_secretsmanager_endpoint ? data.aws_subnet.any_subnet.vpc_id : ""
  # Subnet IDs where endpoint ENI will be created
  # Same subnets as the EC2 instances that need Secrets Manager access
  secretsmanager_subnet_ids = var.enable_secretsmanager_endpoint ? var.subnet_ids : []
  # Security group for the VPC endpoint
  # Allows inbound HTTPS (443) from EC2 instances
  secretsmanager_sg_ids = var.enable_secretsmanager_endpoint ? [aws_security_group.endpoints_sg[0].id] : []
  # VPC CIDR block for endpoint security group egress rules
  # Restricts outbound traffic to stay within VPC only
  vpc_cidr_block = var.enable_secretsmanager_endpoint ? data.aws_vpc.target_vpc.cidr_block : ""
}
################################################################################
# VPC INTERFACE ENDPOINT FOR SECRETS MANAGER
#
# Endpoint Type: Interface (NOT Gateway)
# - Creates ENI (Elastic Network Interface) in each specified subnet
# - Provides private IP addresses within your VPC
# - Requires private DNS enabled for seamless Secrets Manager API calls
#
# Key Requirements:
# ✅ private_dns_enabled = true (mandatory for standard AWS SDK calls)
# ✅ Security group must allow HTTPS (443) inbound from EC2
# ✅ EC2 security group must allow HTTPS (443) outbound
#
# How It Works:
# 1. Your application calls: secretsmanager.get_secret_value(SecretId='mydb')
# 2. AWS SDK resolves: secretsmanager.{region}.amazonaws.com
# 3. Private DNS routes to endpoint's private IP (10.x.x.x)
# 4. Request goes through VPC endpoint (no internet needed)
# 5. Secrets Manager returns the secret value
################################################################################
# Secrets Manager VPC Interface Endpoint
# Purpose: Private access to AWS Secrets Manager API
# - Allows fetching secrets without internet access
# - Supports all Secrets Manager API operations
# - Enables automatic secret rotation in private subnets
resource "aws_vpc_endpoint" "secretsmanager" {
  count = var.enable_secretsmanager_endpoint ? 1 : 0
  vpc_id              = local.secretsmanager_vpc_id
  service_name        = local.secretsmanager_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.secretsmanager_subnet_ids
  security_group_ids  = local.secretsmanager_sg_ids
  # CRITICAL: Private DNS must be enabled
  # This allows standard AWS SDK calls to work without code changes
  # secretsmanager.{region}.amazonaws.com → private IP (10.x.x.x)
  # Without this, you'd need to use endpoint-specific DNS names
  private_dns_enabled = true
  tags = {
    Name        = "${var.env}-${var.project_id}-${data.aws_vpc.target_vpc.id}-secretsmanager-endpoint"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "SecretsManager-VPC-Endpoint"
    Service     = "SecretsManager"
  }
}
