
################################################################################
# Security Group for Redis
################################################################################

resource "aws_security_group" "redis" {
  count = var.enable_ec2_redis ? 1 : 0

  name        = "${var.env}-${var.project_id}-redis-sg"
  description = "Security group for Redis EC2 instance"
  vpc_id      = var.vpc_id

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-redis-sg"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "Redis-SecurityGroup"
    },
    var.tags
  )
}

# Allow Redis access from application security groups
resource "aws_security_group_rule" "redis_from_app_sg" {
  count = var.enable_ec2_redis && length(var.allowed_security_group_ids) > 0 ? length(var.allowed_security_group_ids) : 0

  type                     = "ingress"
  from_port                = var.redis_port
  to_port                  = var.redis_port
  protocol                 = "tcp"
  source_security_group_id = var.allowed_security_group_ids[count.index]
  security_group_id        = aws_security_group.redis[0].id
  description              = "Redis access from application security group"
}

# Allow Redis access from CIDR blocks
resource "aws_security_group_rule" "redis_from_cidr" {
  count = var.enable_ec2_redis && length(var.allowed_cidr_blocks) > 0 ? 1 : 0

  type              = "ingress"
  from_port         = var.redis_port
  to_port           = var.redis_port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.redis[0].id
  description       = "Redis access from allowed CIDR blocks"
}

# Allow all outbound traffic (for updates, CloudWatch, etc.)
resource "aws_security_group_rule" "redis_outbound" {
  count = var.enable_ec2_redis ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.redis[0].id
  description       = "Allow all outbound traffic"
}
