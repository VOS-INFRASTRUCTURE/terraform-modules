################################################################################
# SECURITY GROUP FOR SSM CONTACTS VPC ENDPOINT
#
# Purpose: Controls network access to the SSM Contacts VPC Interface Endpoint
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
# │   - Resources initiate connection to SSM Contacts                       │
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
#
# Security Considerations:
# - Only HTTPS (443) is allowed inbound (encrypted)
# - Source must be from allowed security groups (not 0.0.0.0/0)
# - Egress restricted to VPC CIDR (no internet routing)
# - No other protocols allowed
################################################################################

resource "aws_security_group" "endpoints_sg" {
  count = var.enable_ssm_contacts_endpoint ? 1 : 0

  name        = "${var.env}-${var.project_id}-ssm-contacts-endpoint-sg"
  description = "Security group for SSM Contacts VPC Interface Endpoint - allows HTTPS from resources"
  vpc_id      = data.aws_subnet.any_subnet.vpc_id

  # ============================================================================
  # INGRESS RULE: Allow HTTPS (443) from resources (EC2, Lambda, ECS, etc.)
  # ============================================================================
  # Purpose: Resources need to communicate with SSM Contacts endpoint
  # Protocol: HTTPS (TLS encrypted)
  # Source: Resource security groups (passed via var.resources_security_group_ids)
  #
  # Why security group reference instead of CIDR:
  # - More secure (only allows traffic from specific resources)
  # - Dynamic (automatically updates when resources are added/removed)
  # - AWS best practice for VPC endpoint security
  #
  # Traffic pattern:
  # EC2/Lambda/ECS → (outbound 443) → VPC Endpoint (inbound 443)
  #
  # Example API calls that use this:
  # - ssm-contacts:CreateEngagement
  # - ssm-contacts:ListContacts
  # - ssm-contacts:AcceptPage
  ingress {
    description     = "Allow HTTPS from resources for SSM Contacts API calls"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = var.resources_security_group_ids
  }

  # ============================================================================
  # EGRESS RULE: Allow all traffic within VPC
  # ============================================================================
  # Purpose: Return traffic to resources (stateful security group)
  # Protocol: All (security groups are stateful - auto-allows return traffic)
  # Destination: VPC CIDR only (prevents internet access)
  #
  # Security note:
  # Even though "all protocols" sounds broad, it's restricted to VPC CIDR,
  # which means endpoint can ONLY communicate with resources inside the VPC.
  egress {
    description = "Allow return traffic to resources within VPC (stateful security group)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # All protocols (stateful SG auto-filters to return traffic only)
    cidr_blocks = [local.vpc_cidr_block]
  }

  tags = {
    Name        = "${var.env}-${var.project_id}-ssm-contacts-endpoint-sg"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "SSMContacts-VPCEndpoint"
    Description = "Controls access to SSM Contacts VPC Interface Endpoint"
  }
}

