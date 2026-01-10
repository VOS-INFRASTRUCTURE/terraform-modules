################################################################################
# ECS IAM CI/CD User Module
#
# Purpose: Create a dedicated IAM user with least-privilege permissions for
#          deploying to ECS via CI/CD pipelines (GitHub Actions, GitLab CI, etc.)
#
# Security Model:
# - Separate from Terraform admin credentials
# - Least-privilege (only ECS deploy + ECR push)
# - No infrastructure modification permissions
# - Scoped to specific services and repositories
#
# Permissions Granted:
# - ECR: Push/pull images to specified repositories
# - ECS: Update services, register task definitions, describe resources
# - IAM: PassRole for task execution/task roles only
# - CloudWatch Logs: Read application logs (optional)
################################################################################

################################################################################
# Data Sources
################################################################################

data "aws_region" "current" {
  count = var.aws_region == "" ? 1 : 0
}

data "aws_caller_identity" "current" {
  count = var.aws_account_id == "" ? 1 : 0
}

locals {
  region     = var.aws_region != "" ? var.aws_region : data.aws_region.current[0].name
  account_id = var.aws_account_id != "" ? var.aws_account_id : data.aws_caller_identity.current[0].account_id
}

################################################################################
# IAM User
################################################################################

resource "aws_iam_user" "cicd" {
  name = var.user_name

  tags = merge(
    {
      Name        = var.user_name
      Purpose     = "CI/CD"
      ManagedBy   = "Terraform"
      Description = "Dedicated user for CI/CD ECS deployments"
    },
    var.environment != "" ? { Environment = var.environment } : {},
    var.project_id != "" ? { Project = var.project_id } : {},
    var.tags
  )
}

################################################################################
# Access Key for CI/CD
################################################################################

resource "aws_iam_access_key" "cicd" {
  count = var.create_access_key ? 1 : 0

  user    = aws_iam_user.cicd.name
  pgp_key = var.pgp_key
}

################################################################################
# Policy 1: ECR Access (Push/Pull Images)
################################################################################

resource "aws_iam_user_policy" "ecr" {
  name = "${var.policy_name_prefix}-ecr-policy"
  user = aws_iam_user.cicd.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuthToken"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRImageOperations"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages"
        ]
        Resource = var.ecr_repository_arns
      }
    ]
  })
}

################################################################################
# Policy 2: ECS Deployment (Conditional)
################################################################################

resource "aws_iam_user_policy" "ecs" {
  count = var.enable_ecs_permissions ? 1 : 0

  name = "${var.policy_name_prefix}-ecs-policy"
  user = aws_iam_user.cicd.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "ECSDescribeResources"
          Effect = "Allow"
          Action = [
            "ecs:DescribeTaskDefinition",
            "ecs:DescribeServices",
            "ecs:DescribeTasks",
            "ecs:ListTasks",
            "ecs:DescribeClusters",
            "ecs:ListTaskDefinitions",
            "ecs:DescribeTaskSets"
          ]
          Resource = "*"
          # Note: ecs:wait commands (like wait tasks-stopped) don't require
          # separate permissions - they internally use ecs:DescribeTasks
          # which is already granted above
        },
        {
          Sid    = "ECSRegisterTaskDefinition"
          Effect = "Allow"
          Action = [
            "ecs:RegisterTaskDefinition",
            "ecs:DeregisterTaskDefinition"
          ]
          Resource = "*"
        }
      ],
      length(var.ecs_service_arns) > 0 ? [
        {
          Sid    = "ECSUpdateSpecificServices"
          Effect = "Allow"
          Action = [
            "ecs:UpdateService",
            "ecs:UpdateServicePrimaryTaskSet"
          ]
          Resource = var.ecs_service_arns
        }
      ] : [],
      length(var.task_definition_family_prefixes) > 0 ? [
        {
          Sid    = "ECSRunStopTasks"
          Effect = "Allow"
          Action = [
            "ecs:RunTask",
            "ecs:StopTask"
          ]
          Resource = [
            for prefix in var.task_definition_family_prefixes :
            "arn:aws:ecs:${local.region}:${local.account_id}:task-definition/${prefix}*"
          ]
        }
      ] : [],
      length(var.task_execution_role_arns) > 0 || length(var.task_role_arns) > 0 ? [
        {
          Sid    = "IAMPassRoleForECS"
          Effect = "Allow"
          Action = [
            "iam:PassRole"
          ]
          Resource = concat(var.task_execution_role_arns, var.task_role_arns)
          Condition = {
            StringEquals = {
              "iam:PassedToService" = "ecs-tasks.amazonaws.com"
            }
          }
        }
      ] : []
    )
  })
}

################################################################################
# Policy 3: CloudWatch Logs (Conditional - Read-only for verification)
################################################################################

resource "aws_iam_user_policy" "logs" {
  count = var.enable_cloudwatch_logs_permissions && length(var.log_group_arns) > 0 ? 1 : 0

  name = "${var.policy_name_prefix}-logs-policy"
  user = aws_iam_user.cicd.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsReadAccess"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = flatten([
          for arn in var.log_group_arns : [
            arn,
            "${arn}:*"
          ]
        ])
      }
    ]
  })
}

################################################################################
# Additional Policy Attachments (Optional)
################################################################################

resource "aws_iam_user_policy_attachment" "additional" {
  count = length(var.additional_policy_arns)

  user       = aws_iam_user.cicd.name
  policy_arn = var.additional_policy_arns[count.index]
}

