################################################################################
# Laravel Horizon ECS Task Definition Module
#
# Purpose: Create a reusable ECS task definition for Laravel Horizon queue
#          workers running under supervisord on AWS Fargate.
#
# Container layout (single container per task):
#   supervisord (PID 1) → php artisan horizon → worker pool
#
# Why supervisord?
#   ECS tasks have exactly one PID 1. supervisord acts as PID 1 and manages
#   Horizon as a child process. If Horizon crashes, supervisord restarts it
#   immediately (autorestart=true) without ECS ever replacing the task.
#   This keeps recovery time under 2 seconds with zero job loss.
#
# Graceful shutdown (zero job loss during deployment):
#   ECS sends SIGTERM → supervisord → Horizon enters TERMINATING state →
#   finishes in-flight jobs on all workers → exits cleanly.
#   Set stop_timeout long enough to cover your slowest job.
#
# No inbound traffic:
#   This task has no port mappings. It reads from Redis queues via BLPOP.
#   Security Group should allow OUTBOUND 6379 (Redis) and 3306 (RDS) only.
#
# Scaling:
#   Desired count is typically 1. Scale horizontally by adding more tasks,
#   or vertically by increasing CPU/memory for faster job processing.
#   Horizon itself manages worker concurrency per queue within one task.
#
# ⚠️ Dockerfile requirement:
#   Your Laravel app image must have supervisord installed and an entrypoint
#   that starts supervisord with a config pointing to 'php artisan horizon'.
#   Example supervisord.conf program entry:
#
#     [program:horizon]
#     command=php /var/www/html/artisan horizon
#     autostart=true
#     autorestart=true
#     stopwaitsecs=3600       ; must be >= your longest job runtime
#     stopsignal=SIGTERM
#     stdout_logfile=/dev/stdout
#     stdout_logfile_maxbytes=0
#     stderr_logfile=/dev/stderr
#     stderr_logfile_maxbytes=0
################################################################################


################################################################################
# ECS Task Definition — supervisord + php artisan horizon
################################################################################

resource "aws_ecs_task_definition" "task_definition" {
  family                   = var.task_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = var.cpu
  memory = var.memory

  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.task_role_arn

  # Writable volumes needed when readonlyRootFilesystem = true.
  # supervisord writes PID files to /run/supervisor; php-fpm/horizon writes to /tmp.
  dynamic "volume" {
    for_each = var.enable_readonly_root_filesystem ? [
      { name = "tmp"            },
      { name = "run"            },
      { name = "supervisor-run" },
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
        { sourceVolume = "tmp",            containerPath = "/tmp",            readOnly = false },
        { sourceVolume = "run",            containerPath = "/var/run",        readOnly = false },
        { sourceVolume = "supervisor-run", containerPath = "/run/supervisor", readOnly = false },
      ] : []

      # No portMappings — Horizon pulls from Redis, no inbound connections.

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

      healthCheck = var.health_check_enabled ? {
        command     = ["CMD-SHELL", var.health_check_command]
        interval    = var.health_check_interval
        timeout     = var.health_check_timeout
        retries     = var.health_check_retries
        startPeriod = var.health_check_start_period
      } : null

      # Allow in-flight jobs to finish before ECS kills the container.
      # Must be >= the runtime of your longest-running job.
      # ECS hard-kills after this many seconds regardless.
      stopTimeout = var.stop_timeout
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
