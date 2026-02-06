
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
