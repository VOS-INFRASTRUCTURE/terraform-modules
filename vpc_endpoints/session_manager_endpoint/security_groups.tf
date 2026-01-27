
################################################################################
# Security Group for SSM VPC Interface Endpoints
# - Separate from EC2 SG
# - Inbound: allow HTTPS (443) from EC2 instances
# - Egress: restricted (VPC CIDR) for security
################################################################################


resource "aws_security_group" "endpoints_sg" {

  count               = var.enable_session_manager_endpoints ? 1 : 0

  name        = "${var.env}-${var.project_id}-ssm-endpoints-sg"
  description = "Security group for Internal Private endpoints"
  vpc_id      = data.aws_subnet.any_subnet.vpc_id

  # Allow inbound HTTPS from EC2 SG (all EC2 instances that need Session Manager)
  ingress {
    description                = "Allow HTTPS from EC2 instances for SSM"
    from_port                  = 443
    to_port                    = 443
    protocol                   = "tcp"
    security_groups            = var.resources_security_group_ids # EC2 SGs
  }

  # Egress: restrict to VPC CIDR (stateful SG allows return traffic)
  egress {
    description = "Allow return traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vpc_cidr_block] # only allow within VPC
  }

  tags = {
    Name        = "${var.env}-${var.project_id}-endpoints-sg"
    Environment = var.env
    Project     = var.project_id
  }
}