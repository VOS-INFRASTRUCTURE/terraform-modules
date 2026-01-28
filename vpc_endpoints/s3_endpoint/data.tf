################################################################################
# DATA SOURCES - Auto-discover network configuration
#
# Purpose: Automatically discover VPC and network details from the provided
#          subnet IDs to configure S3 VPC endpoints properly.
#
# This eliminates the need to manually specify:
# - VPC ID
# - VPC CIDR block
# - Region
# - Route tables
################################################################################

# Get current AWS region
# Used to construct S3 endpoint service name
# Example: com.amazonaws.eu-west-2.s3
data "aws_region" "current" {}

# Get subnet details from the first provided subnet
# Used to discover:
# - VPC ID (for creating endpoints in correct VPC)
# - Availability zone information
data "aws_subnet" "any_subnet" {
  id = var.subnet_ids[0]
}

# Get VPC details from the discovered subnet
# Used to retrieve:
# - VPC CIDR block (for security group egress rules)
# - Main route table ID (fallback for Gateway endpoint)
# - VPC configuration details
data "aws_vpc" "target_vpc" {
  id = data.aws_subnet.any_subnet.vpc_id
}

# Get all route tables associated with the subnets
# Used for S3 Gateway endpoint to add routes
# Falls back to main route table if no explicit associations
data "aws_route_tables" "vpc_route_tables" {
  vpc_id = data.aws_subnet.any_subnet.vpc_id

  # Filter for route tables associated with provided subnets
  filter {
    name   = "association.subnet-id"
    values = var.subnet_ids
  }
}
