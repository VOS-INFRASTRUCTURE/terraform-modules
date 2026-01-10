################################################################################
# Module: ECS Task Execution Role
#
# Purpose: Create an IAM role for ECS Fargate task execution with permissions
#          to pull images from ECR, write logs to CloudWatch, and access
#          secrets from SSM/Secrets Manager.
#
# Note: This is the role ECS itself uses, not your application code.
#       For application permissions, create a separate "task role."
################################################################################


################################################################################
# Task Execution Role
################################################################################

resource "aws_iam_role" "ecs_task_execution" {
  name        = var.role_name != "" ? var.role_name : "${var.env}-ecs-task-execution-role"
  description = "ECS Task Execution Role for Fargate tasks"

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
# Attach AWS Managed Policy for ECS Task Execution
#
# This policy grants permissions to:
# - Pull images from ECR (ecr:GetAuthorizationToken, ecr:BatchCheckLayerAvailability, etc.)
# - Write logs to CloudWatch (logs:CreateLogStream, logs:PutLogEvents)
################################################################################

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

################################################################################
# Additional Policy: Access to Secrets Manager (conditional)
################################################################################

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  count = var.enable_secrets_access ? 1 : 0

  name = "${var.env}-ecs-task-execution-secrets-policy"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "ssm:GetParameters"
        ]
        Resource = "*"
      }
    ]
  })
}

