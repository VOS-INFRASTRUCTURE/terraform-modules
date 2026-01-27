################################################################################
# DATA SOURCES - Auto-discover network configuration
#
# Purpose: Automatically discover VPC and network details from the provided
#          subnet IDs to configure Session Manager endpoints properly.
#
# This eliminates the need to manually specify:
# - VPC ID
# - VPC CIDR block
# - Region
################################################################################

# Get current AWS region
# Used to construct Session Manager endpoint service names
# Example: com.amazonaws.eu-west-2.ssm
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
# - VPC configuration details
data "aws_vpc" "target_vpc" {
  id = data.aws_subnet.any_subnet.vpc_id
}

