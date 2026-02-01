################################################################################
# IAM Role for EC2 Qdrant Instance
#
# Purpose: Grant EC2 instance permissions to access AWS services
#
# Permissions:
# - Secrets Manager: Read Qdrant API keys
# - S3: Write backups/snapshots to backup bucket (no delete for safety)
# - CloudWatch: Send logs and metrics
# - Systems Manager: Session Manager access (no SSH keys needed)
################################################################################

resource "aws_iam_role" "qdrant_ec2" {
  name = "${local.instance_name}-role"

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
    var.tags,
    {
      Name        = "${local.instance_name}-role"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
    }
  )
}

resource "aws_iam_instance_profile" "qdrant_ec2" {
  name = "${local.instance_name}-profile"
  role = aws_iam_role.qdrant_ec2.name

  tags = merge(
    var.tags,
    {
      Name        = "${local.instance_name}-profile"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
    }
  )
}

# Attach Systems Manager policy for SSH-less access
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  count      = var.enable_ssm_access ? 1 : 0
  role       = aws_iam_role.qdrant_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

################################################################################
# Policy: Secrets Manager Access
################################################################################

resource "aws_iam_role_policy" "qdrant_secrets_manager" {
  name = "${local.instance_name}-secrets-manager"
  role = aws_iam_role.qdrant_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"     # Read secret metadata
        ]
        Resource = [
          aws_secretsmanager_secret.qdrant_api_key.arn,
        ]
      }
    ]
  })
}

################################################################################
# Policy: S3 Backup Access
################################################################################

resource "aws_iam_role_policy" "qdrant_s3_backup" {
  count = var.enable_automated_backups ? 1 : 0
  name  = "${local.instance_name}-s3-backup"
  role  = aws_iam_role.qdrant_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = [
          var.create_backup_bucket ? aws_s3_bucket.backup[0].arn : "arn:aws:s3:::${var.backup_s3_bucket_name}",
          var.create_backup_bucket ? "${aws_s3_bucket.backup[0].arn}/*" : "arn:aws:s3:::${var.backup_s3_bucket_name}/*"
        ]
      }
    ]
  })
}

################################################################################
# Policy: CloudWatch Logs and Metrics
################################################################################

resource "aws_iam_role_policy" "qdrant_cloudwatch" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  name  = "${local.instance_name}-cloudwatch"
  role  = aws_iam_role.qdrant_ec2.id

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
    ]
  })
}

################################################################################
# Policy: Systems Manager Session Manager
################################################################################

resource "aws_iam_role_policy_attachment" "qdrant_ssm" {
  role       = aws_iam_role.qdrant_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

