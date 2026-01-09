################################################################################
# Module: ECS Task Role
#
# Purpose: Create an IAM role for ECS tasks (application runtime permissions).
#          This role is assumed by your application containers to access AWS services.
#
# Key Permissions:
# - ECS Exec (SSM Session Manager) - for debugging via `aws ecs execute-command`
# - Optional: S3, DynamoDB, SES, etc. (add as needed for your application)
#
# Note: This is different from the Task Execution Role, which ECS itself uses
#       to pull images and write logs.
################################################################################


################################################################################
# ECS Task Role
################################################################################

resource "aws_iam_role" "ecs_task_role" {
  name        = var.role_name != "" ? var.role_name : "${var.env}-ecs-task-role"
  description = "ECS Task Role for application runtime permissions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "ECS"
  }
}

################################################################################
# ECS Exec Policy (for `aws ecs execute-command` debugging)
#
# Grants permissions to use SSM Session Manager for interactive shell access
# to running containers. Required when enable_execute_command = true in ECS service.
################################################################################

resource "aws_iam_role_policy" "ecs_exec" {
  count = var.enable_ecs_exec ? 1 : 0

  name = "${var.env}-ecs-exec-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

################################################################################
# S3 Access Policy (conditional)
#
# Enable if your application needs to read/write to S3 buckets.
################################################################################

resource "aws_iam_role_policy" "s3_access" {
  count = var.enable_s3_access ? 1 : 0

  name = "${var.env}-ecs-s3-access-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = var.s3_bucket_arns
      }
    ]
  })
}


################################################################################
# Secrets Manager Access Policy (conditional)
#
# Enable if your application needs to fetch secrets at runtime (via SDK).
# You can specify exact secret ARNs or use a wildcard pattern.
#
# Note: If secrets are injected as environment variables in task definition,
#       the Task Execution Role needs this permission, not the Task Role.
################################################################################

resource "aws_iam_role_policy" "secrets_access" {
  count = var.enable_secrets_access ? 1 : 0

  name = "${var.env}-ecs-secrets-access-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.secrets_arns
      }
    ]
  })
}

################################################################################
# SSM Parameter Store Access Policy (conditional)
#
# Enable if your application needs to fetch parameters at runtime (via SDK).
# You can specify exact parameter ARNs or use a wildcard pattern.
#
# Note: If parameters are injected as environment variables in task definition,
#       the Task Execution Role needs this permission, not the Task Role.
################################################################################

resource "aws_iam_role_policy" "parameter_store_access" {
  count = var.enable_parameter_store_access ? 1 : 0

  name = "${var.env}-ecs-parameter-store-access-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = var.parameter_arns
      }
    ]
  })
}

