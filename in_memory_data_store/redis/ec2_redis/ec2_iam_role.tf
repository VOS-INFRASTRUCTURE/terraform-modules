
################################################################################
# IAM Role for EC2 Instance
################################################################################

resource "aws_iam_role" "redis" {
  count = var.enable_ec2_redis ? 1 : 0

  name = "${var.env}-${var.project_id}-redis-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-redis-role"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
    },
    var.tags
  )
}

# Attach Systems Manager policy for SSH-less access
resource "aws_iam_role_policy_attachment" "redis_ssm" {
  count = var.enable_ec2_redis && var.enable_ssh_access ? 1 : 0

  role       = aws_iam_role.redis[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch monitoring policy
resource "aws_iam_role_policy" "redis_cloudwatch" {
  count = var.enable_ec2_redis && (var.enable_cloudwatch_monitoring || var.enable_cloudwatch_logs) ? 1 : 0

  name = "${var.env}-${var.project_id}-redis-cloudwatch"
  role = aws_iam_role.redis[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
      # TODO: Future Enhancement - SSM Parameter Store Integration
      # When implementing Redis configuration via SSM Parameter Store:
      # {
      #   Effect = "Allow"
      #   Action = [
      #     "ssm:GetParameter",        # Read Redis password/config from Parameter Store
      #     "ssm:PutParameter"         # Update Redis parameters dynamically
      #   ]
      #   Resource = [
      #     "arn:aws:ssm:${region}:${account}:parameter/${var.env}/${var.project_id}/redis/*"
      #   ]
      # },
      # {
      #   Effect = "Allow"
      #   Action = [
      #     "ec2:DescribeInstances",   # Required for auto-discovery in multi-instance setups
      #     "ec2:DescribeTags"         # Read instance tags for configuration
      #   ]
      #   Resource = "*"
      # }
      #
      # Use Cases:
      # - Store Redis password in SSM Parameter Store instead of user_data
      # - Dynamic configuration updates without instance restart
      # - Auto-discovery of Redis cluster nodes (future clustering support)
      # - Centralized configuration management across environments
    ]
  })
}

# S3 backup policy (if backups enabled)
resource "aws_iam_role_policy" "redis_s3_backup" {
  count = var.enable_ec2_redis && var.enable_automated_backups && var.backup_s3_bucket_name != "" ? 1 : 0

  name = "${var.env}-${var.project_id}-redis-s3-backup"
  role = aws_iam_role.redis[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.backup_s3_bucket_name}",
          "arn:aws:s3:::${var.backup_s3_bucket_name}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "redis" {
  count = var.enable_ec2_redis ? 1 : 0

  name = "${var.env}-${var.project_id}-redis-profile"
  role = aws_iam_role.redis[0].name

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-redis-profile"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
    },
    var.tags
  )
}
