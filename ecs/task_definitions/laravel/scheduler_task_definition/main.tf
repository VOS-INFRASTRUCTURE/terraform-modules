################################################################################
# Laravel Scheduler ECS Task Definition Module
#
# Purpose: Create a reusable ECS task definition for the Laravel scheduler
#          running as an ephemeral Fargate task triggered by EventBridge.
#
# How it works:
#   1. EventBridge Scheduler fires ecs:RunTask every 1 minute
#   2. ECS starts this task — runs `php artisan schedule:run`
#   3. Laravel checks which scheduled commands are due and runs them
#   4. Task exits (~5–15 seconds) — ECS stops and deregisters it automatically
#   5. Cost: ~$0.0001 per invocation (very cheap)
#
# Why RunTask (not a long-running service)?
#   The traditional approach (crontab on a server) doesn't work in Fargate.
#   RunTask + EventBridge replaces cron cleanly: no idle resource, no
#   single-point-of-failure, and each run gets a fresh container.
#
# Duplicate-run protection (onOneServer):
#   If EventBridge accidentally fires twice in the same minute, both tasks
#   race to acquire a Redis lock via SETNX. Only one proceeds; the other exits.
#   Use ->onOneServer() in your Laravel schedule definitions.
#
# No inbound traffic:
#   This task has no port mappings. Its only outbound connections are to
#   Redis (for locks) and RDS (for inline database commands).
#
# ⚠️ Dockerfile requirement:
#   The container command is overridden to ["php", "artisan", "schedule:run"].
#   Your image's working directory must be the Laravel project root (where
#   artisan lives). Override scheduler_command if your setup differs.
#
# ⚠️ EventBridge IAM role (not created here):
#   EventBridge needs an IAM role with ecs:RunTask permission and
#   iam:PassRole for both the execution and task roles. Create that role
#   separately and reference it in the EventBridge Scheduler resource.
################################################################################


################################################################################
# ECS Task Definition — php artisan schedule:run (ephemeral)
################################################################################

resource "aws_ecs_task_definition" "task_definition" {
  family                   = var.task_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = var.cpu
  memory = var.memory

  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.task_role_arn

  # Minimal writable volumes when readonlyRootFilesystem = true.
  # The scheduler task only needs /tmp for any transient file operations.
  dynamic "volume" {
    for_each = var.enable_readonly_root_filesystem ? [
      { name = "tmp" },
      { name = "run" },
    ] : []
    content {
      name = volume.value.name
    }
  }

  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = "${var.ecr_repository_url}:${var.image_tag}"
      essential = true

      readonlyRootFilesystem = var.enable_readonly_root_filesystem

      mountPoints = var.enable_readonly_root_filesystem ? [
        { sourceVolume = "tmp", containerPath = "/tmp",     readOnly = false },
        { sourceVolume = "run", containerPath = "/var/run", readOnly = false },
      ] : []

      # Override the default image entrypoint/cmd to run the scheduler.
      # The task exits when this command returns (success or failure).
      command = var.scheduler_command

      # No portMappings — ephemeral task, no inbound connections.

      secrets     = var.secrets
      environment = var.environment_variables

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_task_log_group.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = var.log_stream_prefix
        }
      }

      # No health check for ephemeral tasks.
      # The task runs once and exits; ECS tracks success via exit code.
    }
  ])

  # Prevents Terraform from reverting image tags that CI/CD has updated.
  lifecycle {
    ignore_changes = [container_definitions]
  }

  tags = merge(
    {
      Name      = var.task_family
      ManagedBy = "Terraform"
      Purpose   = "ECS Task Definition"
    },
    var.environment != "" ? { Environment = var.environment } : {},
    var.project_id != "" ? { Project = var.project_id } : {},
    var.tags
  )
}
