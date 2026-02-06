
################################################################################
# IAM Role for EC2 Instance
################################################################################

resource "aws_iam_role" "ec2_x86_docker" {
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
  role       = aws_iam_role.ec2_x86_docker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Policy for Secrets Manager - READ-ONLY access
# Security Note: EC2 instance can only READ passwords from Secrets Manager.
# Terraform creates/updates/deletes secrets, not the EC2 instance.
# This prevents compromised EC2 from modifying or deleting passwords.
resource "aws_iam_role_policy" "secrets_read_only" {
  name = "${local.instance_name}-secrets-read-only"
  role = aws_iam_role.ec2_x86_docker.id

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
  role  = aws_iam_role.ec2_x86_docker.id

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


# Instance profile is required to attach IAM role to EC2 instance
# Only a profile can be attached to an EC2 instance
# IAM role cannot be attached directly
resource "aws_iam_instance_profile" "ec2_x86_docker" {
  name = "${local.instance_name}-profile"
  role = aws_iam_role.ec2_x86_docker.name

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
