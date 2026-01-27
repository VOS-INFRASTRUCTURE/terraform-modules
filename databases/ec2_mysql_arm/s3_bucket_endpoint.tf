################################################################################
# S3 Gateway VPC Endpoint for Private S3 Access (No NAT Gateway Required)
#
# Purpose: Allows EC2 instances in private subnets to access S3 directly
#          without NAT Gateway or internet access.
#
# How it works:
# - VPC Gateway Endpoint adds a route to S3 in the specified route tables
# - Traffic to S3 stays within AWS network (no internet gateway/NAT)
# - Reduces NAT Gateway costs (~$32/month savings)
# - Improves security (no public IP/internet exposure)
#
# When to enable:
# - EC2 in private subnet needs S3 access (backups, logs, etc.)
# - Want to avoid NAT Gateway costs
# - Don't need other internet access (or have NAT for that separately)
#
# Policy: Restricts endpoint to only access the MySQL backup bucket (if created)
#
# Note: This file is self-contained and discovers VPC/subnet information
#       from the EC2 instance created in main.tf
################################################################################

################################################################################
# Variable - Toggle for S3 Endpoint Creation
################################################################################

variable "enable_s3_endpoint" {
  description = "Enable S3 Gateway VPC Endpoint for private S3 access without NAT Gateway (completely FREE, saves NAT costs)"
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

# Get VPC details to find main route table
data "aws_vpc" "mysql_vpc" {
  count = var.enable_s3_endpoint ? 1 : 0
  id    = data.aws_subnet.mysql_subnet[0].vpc_id
}

# Get all route tables in the VPC
data "aws_route_tables" "vpc_route_tables" {
  count  = var.enable_s3_endpoint ? 1 : 0
  vpc_id = data.aws_subnet.mysql_subnet[0].vpc_id

  # Filter for route tables associated with our subnet
  filter {
    name   = "association.subnet-id"
    values = [var.subnet_id]
  }
}

################################################################################
# Locals
################################################################################

locals {
  # S3 service name for the current region
  s3_service_name = "com.amazonaws.${data.aws_region.current.name}.s3"

  # Determine if we should create the S3 endpoint (controlled by variable)
  should_create_endpoint = var.enable_s3_endpoint

  # Check if backup bucket exists (to restrict policy)
  has_backup_bucket = var.enable_automated_backups

  # VPC ID from subnet
  vpc_id = local.should_create_endpoint ? data.aws_subnet.mysql_subnet[0].vpc_id : ""

  # Route table IDs to associate with the endpoint
  # Use discovered route tables, or fall back to main route table if subnet has no explicit association
  route_table_ids = local.should_create_endpoint ? (
    length(data.aws_route_tables.vpc_route_tables[0].ids) > 0
      ? data.aws_route_tables.vpc_route_tables[0].ids
      : [data.aws_vpc.mysql_vpc[0].main_route_table_id]
  ) : []

  # Endpoint policy: Restrict to backup bucket if it exists, else allow all S3
  s3_endpoint_policy = local.has_backup_bucket ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "S3AccessToBackupBucket"
        Effect    = "Allow"
        Principal = "*"
        Action    = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource  = [
          aws_s3_bucket.mysql_backups[0].arn,
          "${aws_s3_bucket.mysql_backups[0].arn}/*"
        ]
      }
    ]
  }) : jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAllS3"
        Effect    = "Allow"
        Principal = "*"
        Action    = "*"
        Resource  = "*"
      }
    ]
  })
}


################################################################################
# S3 Gateway VPC Endpoint
################################################################################

resource "aws_vpc_endpoint" "s3" {
  count               = local.should_create_endpoint ? 1 : 0
  vpc_id              = local.vpc_id
  service_name        = local.s3_service_name
  vpc_endpoint_type   = "Gateway"
  route_table_ids     = local.route_table_ids
  policy              = local.s3_endpoint_policy

  private_dns_enabled   = true

  tags = {
    Name        = "${var.env}-${var.project_id}-${var.base_name}-s3-endpoint"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "S3-GatewayEndpoint-MySQL-Backups"
  }
}

################################################################################
# Output
################################################################################

output "s3_endpoint" {
  description = "S3 Gateway VPC Endpoint configuration and identifiers"
  value = {
    # Toggle status
    enabled = local.should_create_endpoint

    # Endpoint details (present only when enabled)
    endpoint_id   = local.should_create_endpoint ? aws_vpc_endpoint.s3[0].id : null
    endpoint_arn  = local.should_create_endpoint ? aws_vpc_endpoint.s3[0].arn : null
    service_name  = local.s3_service_name
    endpoint_type = "Gateway"

    # Network configuration
    vpc_id                  = local.vpc_id
    associated_route_tables = local.route_table_ids

    # Policy configuration
    policy_scope      = "RestrictedToBackupBucket"
    backup_bucket_arn = local.should_create_endpoint ? aws_s3_bucket.mysql_backups[0].arn : null

    # Cost estimate
    monthly_cost_estimate = "FREE (Gateway endpoint has no hourly charge, and data transfer between EC2 and S3 in same region is FREE)"
  }
}
