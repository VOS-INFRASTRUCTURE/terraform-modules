################################################################################
# SECURITY GROUP FOR SECRETS MANAGER VPC ENDPOINT
#
# Purpose: Controls network access to Secrets Manager VPC Interface Endpoint
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
# │   - Resources initiate connection to Secrets Manager                    │
# │   - Must use HTTPS for encrypted communication                           │
# │   - Source: Resource security groups (var.resources_security_group_ids) │
# │                                                                           │
# │ Outbound (Egress):                                                       │
# │   VPC Endpoint → All protocols → VPC CIDR only                          │
# │   - Return traffic to resources (stateful connection)                   │
# │   - Restricted to VPC CIDR for security (no internet access)            │
# │   - Uses security group stateful nature (auto-allows responses)         │
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
  count = var.enable_secretsmanager_endpoint ? 1 : 0
  name        = "${var.env}-${var.project_id}-secretsmanager-endpoint-sg"
  description = "Security group for Secrets Manager VPC Interface Endpoint - allows HTTPS from resources"
  vpc_id      = data.aws_subnet.any_subnet.vpc_id
  # ============================================================================
  # INGRESS RULE: Allow HTTPS (443) from resources (EC2, Lambda, ECS, etc.)
  # ============================================================================
  # Purpose: Resources need to communicate with Secrets Manager endpoint
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
  # - secretsmanager.get_secret_value()
  # - secretsmanager.create_secret()
  # - secretsmanager.rotate_secret()
  ingress {
    description     = "Allow HTTPS from resources for Secrets Manager API calls"
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
  # Why allow all protocols:
  # - Security groups are stateful (response traffic is automatically allowed)
  # - This rule allows VPC endpoint to respond to resource requests
  # - Restricted to VPC CIDR for security (no 0.0.0.0/0)
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
    Name        = "${var.env}-${var.project_id}-secretsmanager-endpoint-sg"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "SecretsManager-VPCEndpoint"
    Description = "Controls access to Secrets Manager VPC Interface Endpoint"
  }
}
################################################################################
# SECURITY GROUP VALIDATION NOTES
#
# Resource Security Group Requirements (separate from this file):
# ✅ Outbound HTTPS (443) to VPC CIDR or to this security group
#
# Common Issues:
# ❌ Resource security group blocks outbound 443 → Secrets Manager calls fail
# ❌ Endpoint security group allows 0.0.0.0/0 → Security risk
# ❌ Missing egress rule on endpoint SG → Connection hangs
#
# Testing:
# From EC2 instance, test connectivity:
# $ aws secretsmanager get-secret-value --secret-id my-secret
# Should work without internet access if private DNS is enabled
#
# Using AWS SDK (Python example):
# import boto3
# client = boto3.client('secretsmanager')
# response = client.get_secret_value(SecretId='my-database-password')
# secret = response['SecretString']
#
# Troubleshooting:
# 1. Check resource SG allows outbound 443
# 2. Check endpoint SG allows inbound 443 from resource SG
# 3. Check private DNS is enabled on endpoint
# 4. Verify DNS resolution: nslookup secretsmanager.{region}.amazonaws.com
#    Should resolve to private IP (10.x.x.x)
################################################################################
