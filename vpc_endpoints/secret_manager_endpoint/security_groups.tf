################################################################################
# SECURITY GROUP FOR SESSION MANAGER VPC ENDPOINTS
#
# Purpose: Controls network access to Session Manager VPC Interface Endpoints
#
# Security Model:
# - Separate security group for endpoints (NOT shared with EC2 instances)
# - Follows principle of least privilege
# - Allows only necessary traffic patterns
#
# Traffic Flow:
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ Inbound (Ingress):                                                       │
# │   EC2 Instance (with allowed SG) → HTTPS (443) → VPC Endpoint          │
# │   - EC2 initiates connection to Session Manager                         │
# │   - Must use HTTPS for encrypted communication                           │
# │   - Source: EC2 security groups (var.resources_security_group_ids)      │
# │                                                                           │
# │ Outbound (Egress):                                                       │
# │   VPC Endpoint → All protocols → VPC CIDR only                          │
# │   - Return traffic to EC2 instances (stateful connection)               │
# │   - Restricted to VPC CIDR for security (no internet access)            │
# │   - Uses security group stateful nature (auto-allows responses)         │
# └──────────────────────────────────────────────────────────────────────────┘
#
# Why Separate Security Group:
# ✅ Follows AWS best practices (separate concerns)
# ✅ Easier to audit endpoint access
# ✅ Can be shared across multiple EC2 instances
# ✅ Doesn't require modifying EC2 security groups
# ✅ Centralized management of endpoint access
#
# Security Considerations:
# - Only HTTPS (443) is allowed inbound (encrypted)
# - Source must be from allowed security groups (not 0.0.0.0/0)
# - Egress restricted to VPC CIDR (no internet routing)
# - No SSH, RDP, or other protocols allowed
################################################################################

resource "aws_security_group" "endpoints_sg" {
  count = var.enable_secretsmanager_endpoint ? 1 : 0

  name        = "${var.env}-${var.project_id}-scrt-endpoints-sg"
  description = "Security group for Session Manager VPC Interface Endpoints - allows HTTPS from EC2 instances"
  vpc_id      = data.aws_subnet.any_subnet.vpc_id

  # ============================================================================
  # INGRESS RULE: Allow HTTPS (443) from EC2 instances
  # ============================================================================
  # Purpose: EC2 instances need to communicate with Session Manager endpoints
  # Protocol: HTTPS (TLS encrypted)
  # Source: EC2 security groups (passed via var.resources_security_group_ids)
  #
  # Why security group reference instead of CIDR:
  # - More secure (only allows traffic from specific instances)
  # - Dynamic (automatically updates when instances are added/removed)
  # - AWS best practice for VPC endpoint security
  #
  # Traffic pattern:
  # EC2 Instance → (outbound 443) → VPC Endpoint (inbound 443)
  ingress {
    description     = "Allow HTTPS from EC2 instances for Session Manager communication"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = var.resources_security_group_ids # EC2 security groups
  }

  # ============================================================================
  # EGRESS RULE: Allow all traffic within VPC
  # ============================================================================
  # Purpose: Return traffic to EC2 instances (stateful security group)
  # Protocol: All (security groups are stateful - auto-allows return traffic)
  # Destination: VPC CIDR only (prevents internet access)
  #
  # Why allow all protocols:
  # - Security groups are stateful (response traffic is automatically allowed)
  # - This rule allows VPC endpoint to respond to EC2 requests
  # - Restricted to VPC CIDR for security (no 0.0.0.0/0)
  #
  # Security note:
  # Even though "all protocols" sounds broad, it's restricted to VPC CIDR,
  # which means endpoints can ONLY communicate with resources inside the VPC.
  egress {
    description = "Allow return traffic to EC2 instances within VPC (stateful security group)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # All protocols (stateful SG auto-filters to return traffic only)
    cidr_blocks = [local.vpc_cidr_block] # Restricted to VPC CIDR only
  }

  tags = {
    Name        = "${var.env}-${var.project_id}-scrt-endpoints-sg"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "SessionManager-VPCEndpoints"
    Description = "Controls access to Session Manager VPC Interface Endpoints"
  }
}

################################################################################
# SECURITY GROUP VALIDATION NOTES
#
# EC2 Security Group Requirements (separate from this file):
# ✅ Outbound HTTPS (443) to VPC CIDR or to this security group
# ✅ No inbound SSH (22) required (Session Manager replaces SSH)
#
# Common Issues:
# ❌ EC2 security group blocks outbound 443 → Session Manager fails silently
# ❌ Endpoint security group allows 0.0.0.0/0 → Security risk
# ❌ Missing egress rule on endpoint SG → Connection hangs
#
# Testing:
# From EC2 instance, test connectivity:
# $ curl -I https://ssm.{region}.amazonaws.com
# Should resolve to private IP (10.x.x.x) if private DNS is working
#
# Troubleshooting:
# 1. Check EC2 SG allows outbound 443
# 2. Check endpoint SG allows inbound 443 from EC2 SG
# 3. Check private DNS is enabled on endpoints
# 4. Check SSM Agent is running: systemctl status amazon-ssm-agent
################################################################################

