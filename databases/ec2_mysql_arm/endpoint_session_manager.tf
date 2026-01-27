################################################################################
# AWS Systems Manager (SSM) Session Manager VPC Endpoints
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
# How it works:
# - EC2 instance communicates with SSM via private endpoints
# - Session Manager creates secure tunnel through these endpoints
# - You connect via AWS Console or AWS CLI (no SSH keys needed)
# - Traffic stays within AWS network (no internet gateway/NAT)
#
# Cost comparison (per month):
# - NAT Gateway: ~$32.40 + data transfer
# - 3 SSM Interface Endpoints: ~$21.60 ($7.20 × 3) + minimal data transfer
# - Savings: ~$10/month + improved security
#
# Note: This file is self-contained and discovers VPC/subnet information
#       from the EC2 instance created in main.tf
################################################################################

################################################################################
# Variable - Toggle for Session Manager Endpoints Creation
################################################################################

variable "enable_session_manager_endpoints" {
  description = "Enable Session Manager VPC Interface Endpoints for SSH-less access without NAT Gateway (costs ~$21.60/month for 3 endpoints but saves ~$10/month vs NAT)"
  type        = bool
  default     = false
}

################################################################################
# Security Group for SSM VPC Interface Endpoints
# - Separate from EC2 SG
# - Inbound: allow HTTPS (443) from EC2 instances
# - Egress: restricted (VPC CIDR) for security
################################################################################

resource "aws_security_group" "ssm_endpoints_sg" {
  count       = var.enable_session_manager_endpoints ? 1 : 0

  name        = "${var.env}-${var.project_id}-ssm-endpoints-sg"
  description = "Security group for Session Manager VPC endpoints"
  vpc_id      = local.ssm_vpc_id

  # Allow inbound HTTPS from EC2 SG (all EC2 instances that need Session Manager)
  ingress {
    description                = "Allow HTTPS from EC2 instances for SSM"
    from_port                  = 443
    to_port                    = 443
    protocol                   = "tcp"
    security_groups            = var.security_group_ids # EC2 SGs
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
    Name        = "${var.env}-${var.project_id}-ssm-endpoints-sg"
    Environment = var.env
    Project     = var.project_id
  }
}


################################################################################
# Locals
################################################################################

locals {
  # Session Manager service names for the current region
  ssm_service_name         = "com.amazonaws.${data.aws_region.current.name}.ssm"
  ssmmessages_service_name = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
  ec2messages_service_name = "com.amazonaws.${data.aws_region.current.name}.ec2messages"

  # VPC ID from subnet
  ssm_vpc_id = var.enable_session_manager_endpoints ? data.aws_subnet.mysql_subnet[0].vpc_id : ""

  # Subnet ID where endpoint ENI will be created (same as EC2)
  ssm_subnet_ids = var.enable_session_manager_endpoints ? [var.subnet_id] : []

  # Security group IDs - Use same as EC2 instance
  # Note: The EC2 security group must allow outbound HTTPS (443)
  # This is typically already allowed with standard "allow all outbound" rules
  ssm_sg_ids =  [aws_security_group.ssm_endpoints_sg[0].id]  # use the new SG

  # VPC CIDR block for egress rule in SSM endpoints SG
  vpc_cidr_block = data.aws_vpc.mysql_vpc[0].cidr_block

}

################################################################################
# VPC Interface Endpoints for Session Manager
#
# Note: Uses the same security groups as the EC2 instance
# Requirement: EC2 security group must allow outbound HTTPS (443)
#
# Key Facts:
# - ALL THREE endpoints are mandatory (not optional)
# - Must have private_dns_enabled = true
# - Must be Interface endpoints (not Gateway)
# - Missing any one endpoint = Session Manager broken
################################################################################

# Endpoint 1: SSM (Systems Manager API)
# Purpose: Core Systems Manager service communication
resource "aws_vpc_endpoint" "ssm" {
  count               = var.enable_session_manager_endpoints ? 1 : 0
  vpc_id              = local.ssm_vpc_id
  service_name        = local.ssm_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.ssm_subnet_ids
  security_group_ids  = local.ssm_sg_ids

  # REQUIRED: Private DNS must be enabled for Session Manager to work
  private_dns_enabled = true

  tags = {
    Name        = "${var.env}-${var.project_id}-${var.base_name}-ssm-endpoint"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "SessionManager-SSM-Endpoint"
  }
}

# Endpoint 2: SSM Messages (Session Manager messaging)
# Purpose: Handles Session Manager session communication
resource "aws_vpc_endpoint" "ssmmessages" {
  count               = var.enable_session_manager_endpoints ? 1 : 0
  vpc_id              = local.ssm_vpc_id
  service_name        = local.ssmmessages_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.ssm_subnet_ids
  security_group_ids  = local.ssm_sg_ids

  # REQUIRED: Private DNS must be enabled for Session Manager to work
  private_dns_enabled = true

  tags = {
    Name        = "${var.env}-${var.project_id}-${var.base_name}-ssmmessages-endpoint"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "SessionManager-SSMMessages-Endpoint"
  }
}

# Endpoint 3: EC2 Messages (EC2 instance communication)
# Purpose: Allows EC2 instance to communicate with Systems Manager
resource "aws_vpc_endpoint" "ec2messages" {
  count               = var.enable_session_manager_endpoints ? 1 : 0
  vpc_id              = local.ssm_vpc_id
  service_name        = local.ec2messages_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.ssm_subnet_ids
  security_group_ids  = local.ssm_sg_ids

  # REQUIRED: Private DNS must be enabled for Session Manager to work
  private_dns_enabled = true

  tags = {
    Name        = "${var.env}-${var.project_id}-${var.base_name}-ec2messages-endpoint"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "SessionManager-EC2Messages-Endpoint"
  }
}

################################################################################
# Output
################################################################################

output "session_manager_endpoints" {
  description = "Session Manager VPC Interface Endpoints configuration and identifiers"
  value = {
    # Toggle status
    enabled = var.enable_session_manager_endpoints

    # SSM Endpoint
    ssm = {
      endpoint_id         = var.enable_session_manager_endpoints ? aws_vpc_endpoint.ssm[0].id : null
      endpoint_arn        = var.enable_session_manager_endpoints ? aws_vpc_endpoint.ssm[0].arn : null
      service_name        = local.ssm_service_name
      private_dns_enabled = true
      dns_entries         = var.enable_session_manager_endpoints ? aws_vpc_endpoint.ssm[0].dns_entry : []
    }

    # SSM Messages Endpoint
    ssmmessages = {
      endpoint_id         = var.enable_session_manager_endpoints ? aws_vpc_endpoint.ssmmessages[0].id : null
      endpoint_arn        = var.enable_session_manager_endpoints ? aws_vpc_endpoint.ssmmessages[0].arn : null
      service_name        = local.ssmmessages_service_name
      private_dns_enabled = true
      dns_entries         = var.enable_session_manager_endpoints ? aws_vpc_endpoint.ssmmessages[0].dns_entry : []
    }

    # EC2 Messages Endpoint
    ec2messages = {
      endpoint_id         = var.enable_session_manager_endpoints ? aws_vpc_endpoint.ec2messages[0].id : null
      endpoint_arn        = var.enable_session_manager_endpoints ? aws_vpc_endpoint.ec2messages[0].arn : null
      service_name        = local.ec2messages_service_name
      private_dns_enabled = true
      dns_entries         = var.enable_session_manager_endpoints ? aws_vpc_endpoint.ec2messages[0].dns_entry : []
    }

    # Network configuration
    vpc_id             = local.ssm_vpc_id
    subnet_ids         = local.ssm_subnet_ids
    security_group_ids = local.ssm_sg_ids

    # Cost estimate
    monthly_cost_estimate = var.enable_session_manager_endpoints ? "~$21.60 USD (3 Interface endpoints × $7.20 each) + minimal data transfer" : "$0 (endpoints disabled, requires NAT Gateway or public internet for Session Manager)"

    # Validation reminder
    all_three_endpoints_required = "⚠️ ALL THREE endpoints (ssm, ssmmessages, ec2messages) are MANDATORY. Missing even one will break Session Manager completely!"
  }
}

