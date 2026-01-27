
################################################################################
# Data Sources - Auto-discover network configuration from EC2 instance
################################################################################
data "aws_region" "current" {}

# Get subnet details from the EC2 instance
data "aws_subnet" "any_subnet" {
  id    = var.subnet_ids[0]
}

# Get VPC details to find main route table
data "aws_vpc" "target_vpc" {
  id    = data.aws_subnet.any_subnet.vpc_id
}

