
################################################################################
# Data Sources - Auto-discover network configuration from EC2 instance
################################################################################

# Get subnet details from the EC2 instance
data "aws_subnet" "pgsql_subnet" {
  id    = var.subnet_id
}

# Get VPC details to find main route table
data "aws_vpc" "pgsql_vpc" {
  id    = data.aws_subnet.pgsql_subnet.vpc_id
}

# # Get all route tables in the VPC
# data "aws_route_tables" "vpc_route_tables" {
#   vpc_id = data.aws_subnet.pgsql_subnet.vpc_id
#
#   # Filter for route tables associated with our subnet
#   filter {
#     name   = "association.subnet-id"
#     values = [var.subnet_id]
#   }
# }
