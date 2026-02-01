################################################################################
# Data Sources - Auto-discover network configuration from EC2 instance
################################################################################

# Get subnet details from the EC2 instance
data "aws_subnet" "qdrant_subnet" {
  id = var.subnet_id
}

