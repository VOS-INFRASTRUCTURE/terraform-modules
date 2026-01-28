################################################################################
# AWS S3 VPC ENDPOINTS MODULE
#
# Purpose: Provides two types of VPC endpoints for private S3 access without
#          NAT Gateway or internet access.
#
# Endpoint Types:
# 1. Gateway Endpoint (FREE, recommended for most use cases)
#    - No hourly charges
#    - Works via route table modifications
#    - Supports endpoint policies
#    - Best for EC2 instances with route table access
#
# 2. Interface Endpoint ($7.20/month per AZ)
#    - Creates ENI with private IP in your subnet
#    - Works when route tables can't be modified
#    - Provides private DNS
#    - Best for fully isolated architectures
#
# When to Use Gateway vs Interface:
# - Gateway: Default choice, FREE, works for most cases
# - Interface: When Gateway doesn't work (no NAT, strict security)
#
# Cost Comparison:
# - Gateway: FREE (no hourly charge, free data transfer in same region)
# - Interface: ~$7.20/month per AZ + free data transfer
# - NAT Gateway (avoided): ~$32.40/month + $0.045/GB
################################################################################
################################################################################
# LOCALS - Computed Values
################################################################################
locals {
  # S3 service name for the current region
  s3_service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  # VPC CIDR block for endpoint security group egress rules
  vpc_cidr_block = data.aws_vpc.target_vpc.cidr_block
  # Determine which endpoint types to create
  # Interface endpoint requires gateway endpoint. So gateway is created if either is enabled.
  create_gateway_endpoint   = var.enable_s3_gateway_endpoint || var.enable_s3_interface_endpoint
  create_interface_endpoint = var.enable_s3_interface_endpoint

  # Route table IDs for Gateway endpoint
  route_table_ids = local.create_gateway_endpoint ? (
    length(data.aws_route_tables.vpc_route_tables.ids) > 0
    ? data.aws_route_tables.vpc_route_tables.ids
    : [data.aws_vpc.target_vpc.main_route_table_id]
  ) : []
  # Build S3 endpoint policy based on provided bucket ARNs
  s3_endpoint_policy = length(var.s3_bucket_arns) > 0 ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "RestrictToSpecificBuckets"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          # "s3:DeleteObject",
          # "s3:GetBucketLocation"
        ]
        Resource = flatten([
          for arn in var.s3_bucket_arns : [arn, "${arn}/*"]
        ])
      }
    ]
  }) : jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAllS3"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:*"
        Resource  = "*"
      }
    ]
  })
}
