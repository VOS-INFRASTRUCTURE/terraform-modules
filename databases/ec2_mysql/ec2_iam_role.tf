
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

# Policy for Secrets Manager - READ-ONLY access
# Security Note: EC2 instance can only READ passwords from Secrets Manager.
# Terraform creates/updates/deletes secrets, not the EC2 instance.
# This prevents compromised EC2 from modifying or deleting passwords.
resource "aws_iam_role_policy" "secrets_read_only" {
  name = "${local.instance_name}-secrets-read-only"
  role = aws_iam_role.mysql_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSecretsOnly"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",    # Read password value
          "secretsmanager:DescribeSecret"     # Read secret metadata
          # NOTE: The following permissions are NOT granted for security:
          # - secretsmanager:CreateSecret
          # - secretsmanager:UpdateSecret
          # - secretsmanager:DeleteSecret
          # - secretsmanager:PutSecretValue
          # Only Terraform can manage secrets
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
        Sid    = "CloudWatchMetricsAndLogs"
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

# Policy for S3 backups - WRITE-ONLY (no delete permissions)
# Security Note: EC2 instance can only upload backups to S3, not delete them.
# Backup retention is managed by S3 lifecycle rules or administrators.
# This prevents accidental or malicious deletion of backups by compromised EC2.
resource "aws_iam_role_policy" "s3_backup_write_only" {
  count = var.enable_automated_backups && var.backup_s3_bucket_name != "" ? 1 : 0
  name  = "${local.instance_name}-s3-backup-write-only"
  role  = aws_iam_role.mysql_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BackupWriteOnly"
        Effect = "Allow"
        Action = [
          "s3:PutObject",    # Upload backup files to S3
          "s3:GetObject",    # Download backups for verification (optional)
          "s3:ListBucket"    # List existing backups in bucket
          # NOTE: s3:DeleteObject permission intentionally removed for security
          # Backup deletion managed by S3 lifecycle rules or administrators only
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
