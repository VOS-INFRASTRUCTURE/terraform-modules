
################################################################################
# Security Group for ElastiCache
################################################################################

resource "aws_security_group" "elasticache" {
  count = var.enable_elasticache ? 1 : 0

  name        = "${var.env}-${var.project_id}-elasticache-sg"
  description = "Security group for ElastiCache Redis/Valkey cluster"
  vpc_id      = var.vpc_id

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-elasticache-sg"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "ElastiCache-SecurityGroup"
    },
    var.tags
  )
}

# Allow Redis/Valkey access from application security groups
resource "aws_security_group_rule" "elasticache_from_app_sg" {
  count = var.enable_elasticache && length(var.allowed_security_group_ids) > 0 ? length(var.allowed_security_group_ids) : 0

  type                     = "ingress"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  source_security_group_id = var.allowed_security_group_ids[count.index]
  security_group_id        = aws_security_group.elasticache[0].id
  description              = "Redis/Valkey access from application security group"
}

# Allow Redis/Valkey access from CIDR blocks
resource "aws_security_group_rule" "elasticache_from_cidr" {
  count = var.enable_elasticache && length(var.allowed_cidr_blocks) > 0 ? 1 : 0

  type              = "ingress"
  from_port         = var.port
  to_port           = var.port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.elasticache[0].id
  description       = "Redis/Valkey access from allowed CIDR blocks"
}

# Allow all outbound traffic
resource "aws_security_group_rule" "elasticache_outbound" {
  count = var.enable_elasticache ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.elasticache[0].id
  description       = "Allow all outbound traffic"
}