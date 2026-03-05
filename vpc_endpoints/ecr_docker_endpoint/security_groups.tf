################################################################################
# SECURITY GROUP FOR ECR VPC ENDPOINTS
#
# Purpose: Controls network access to the ECR VPC Interface Endpoints
#          (ecr.api, ecr.dkr, and s3 interface)
#
# Security Model:
# - Single shared security group for all three ECR-related endpoints
# - Follows principle of least privilege
# - Allows only HTTPS (443) from resource security groups
#
# Traffic Flow:
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ Inbound (Ingress):                                                       │
# │   ECS/EC2/Lambda (with allowed SG) → HTTPS (443) → VPC Endpoint        │
# │   - Container runtime initiates image pull to ecr.api / ecr.dkr         │
# │   - Layer downloads go to S3 Interface endpoint                         │
# │   - Source: Resource security groups (var.resources_security_group_ids) │
# │                                                                           │
# │ Outbound (Egress):                                                       │
# │   VPC Endpoint → All protocols → VPC CIDR only                          │
# │   - Return traffic to container runtime (stateful connection)           │
# │   - Restricted to VPC CIDR for security (no internet access)            │
# └──────────────────────────────────────────────────────────────────────────┘
#
# Why Separate Security Group:
# ✅ Follows AWS best practices (separate concerns)
# ✅ Easier to audit endpoint access
# ✅ Shared across ecr.api, ecr.dkr, and s3 endpoints (all need same rules)
# ✅ Doesn't require modifying resource security groups
# ✅ Centralized management of endpoint access
#
# Important:
# - Your ECS task / EC2 / Lambda security group MUST allow outbound 443
#   to the VPC CIDR for image pulls to work
################################################################################

resource "aws_security_group" "endpoints_sg" {
  count = var.enable_ecr_endpoints ? 1 : 0

  name        = "${var.env}-${var.project_id}-ecr-endpoints-sg"
  description = "Security group for ECR VPC Interface Endpoints (ecr.api, ecr.dkr, s3) - allows HTTPS from resources"
  vpc_id      = local.vpc_id

  # ============================================================================
  # INGRESS: Allow HTTPS (443) from resources (ECS tasks, EC2, Lambda)
  # ============================================================================
  # Purpose: Container runtimes need HTTPS access to ECR endpoints
  # Protocol: HTTPS (all ECR and S3 traffic is TLS encrypted)
  # Source: Resource security groups (var.resources_security_group_ids)
  dynamic "ingress" {
    for_each = var.resources_security_group_ids
    content {
      description     = "Allow HTTPS from resource security group for image pulls"
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  # ============================================================================
  # EGRESS: Allow all outbound traffic within VPC CIDR only
  # ============================================================================
  # Purpose: Return traffic and responses back to ECS/EC2/Lambda
  # Restricted to VPC CIDR to prevent endpoint from routing internet traffic
  egress {
    description = "Allow all outbound traffic within VPC CIDR"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vpc_cidr_block]
  }

  tags = {
    Name        = "${var.env}-${var.project_id}-ecr-endpoints-sg"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "ECR-VPC-Endpoints-SG"
    Service     = "ECR"
  }
}

