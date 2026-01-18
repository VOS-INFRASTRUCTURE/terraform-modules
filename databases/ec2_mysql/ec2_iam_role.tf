
################################################################################
# IAM Role for EC2 Instance
################################################################################

resource "aws_iam_role" "mysql_ec2" {
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

# Attach Systems Manager policy for SSH-less access
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  count      = var.enable_ssm_access ? 1 : 0
  role       = aws_iam_role.mysql_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Policy to read secrets from Secrets Manager
resource "aws_iam_role_policy" "secrets_access" {
  name = "${local.instance_name}-secrets-access"
  role = aws_iam_role.mysql_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.mysql_root_password.arn,
          aws_secretsmanager_secret.mysql_user_password.arn
        ]
      }
    ]
  })
}

# Policy for CloudWatch logs and metrics
resource "aws_iam_role_policy" "cloudwatch_access" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  name  = "${local.instance_name}-cloudwatch-access"
  role  = aws_iam_role.mysql_ec2.id

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

# Policy for S3 backups
resource "aws_iam_role_policy" "s3_backup_access" {
  count = var.enable_automated_backups && var.backup_s3_bucket_name != "" ? 1 : 0
  name  = "${local.instance_name}-s3-backup-access"
  role  = aws_iam_role.mysql_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.backup_s3_bucket_name}",
          "arn:aws:s3:::${var.backup_s3_bucket_name}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "mysql_ec2" {
  name = "${local.instance_name}-profile"
  role = aws_iam_role.mysql_ec2.name

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
