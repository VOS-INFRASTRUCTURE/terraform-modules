################################################################################
# SECURITY GROUP FOR SSM INCIDENTS VPC ENDPOINT
#
# Purpose: Controls network access to the SSM Incidents VPC Interface Endpoint
#
# Security Model:
# - Separate security group for endpoint (NOT shared with EC2 instances)
# - Follows principle of least privilege
# - Allows only necessary traffic patterns
#
# Traffic Flow:
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ Inbound (Ingress):                                                       │
# │   EC2/Lambda/ECS (with allowed SG) → HTTPS (443) → VPC Endpoint        │
# │   - Resources initiate connection to SSM Incidents API                  │
# │   - Must use HTTPS for encrypted communication                           │
# │   - Source: Resource security groups (var.resources_security_group_ids) │
# │                                                                           │
# │ Outbound (Egress):                                                       │
# │   VPC Endpoint → All protocols → VPC CIDR only                          │
# │   - Return traffic to resources (stateful connection)                   │
# │   - Restricted to VPC CIDR for security (no internet access)            │
# └──────────────────────────────────────────────────────────────────────────┘
#
# Why Separate Security Group:
# ✅ Follows AWS best practices (separate concerns)
# ✅ Easier to audit endpoint access
# ✅ Can be shared across multiple resources (EC2, Lambda, ECS)
# ✅ Doesn't require modifying resource security groups
# ✅ Centralized management of endpoint access
################################################################################

resource "aws_security_group" "endpoints_sg" {
  count = var.enable_ssm_incidents_endpoint ? 1 : 0

  name        = "${var.env}-${var.project_id}-ssm-incidents-endpoint-sg"
  description = "Security group for SSM Incidents VPC Interface Endpoint - allows HTTPS from resources"
  vpc_id      = data.aws_subnet.any_subnet.vpc_id

  # ============================================================================
  # INGRESS: Allow HTTPS (443) from resources (EC2, Lambda, ECS, etc.)
  # ============================================================================
  # Purpose: Resources need to communicate with SSM Incidents endpoint
  # Protocol: HTTPS (TLS encrypted)
  # Source: Resource security groups (passed via var.resources_security_group_ids)
  dynamic "ingress" {
    for_each = var.resources_security_group_ids
    content {
      description     = "Allow HTTPS from resource security group"
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  # ============================================================================
  # EGRESS: Allow all outbound traffic within VPC CIDR only
  # ============================================================================
  # Purpose: Return traffic and responses back to resources
  # Restricted to VPC CIDR to prevent endpoint from being used to access internet
  egress {
    description = "Allow all outbound traffic within VPC CIDR"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vpc_cidr_block]
  }

  tags = {
    Name        = "${var.env}-${var.project_id}-ssm-incidents-endpoint-sg"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "SSMIncidents-VPC-Endpoint-SG"
    Service     = "SSMIncidents"
  }
}

