################################################################################
# Laravel Web ECS Task Definition Module
#
# Purpose: Create a reusable ECS task definition for Laravel web applications
#          running nginx + php-fpm as sidecar containers on AWS Fargate.
#
# Container layout (one ECS task = one unit):
#   nginx    (port 80)   — reverse proxy, ALB target
#   php-fpm  (port 9000) — PHP application, receives proxied requests from nginx
#
# nginx and php-fpm share the task network namespace so nginx can reach
# php-fpm at localhost:9000 without a shared volume for socket communication.
#
# Startup order: php-fpm must be HEALTHY before nginx starts (dependsOn).
#
# ⚠️ IMPORTANT - Configuration Updates & Container Restarts:
# ===========================================================
# Secrets and SSM parameters are injected ONLY at container startup.
# To pick up new values, force a new deployment via:
#   Method 1 (easiest): Re-run the GitHub Actions workflow
#   Method 2: aws ecs update-service --force-new-deployment
#
# ⚠️ IMPORTANT - lifecycle ignore_changes:
# =========================================
# container_definitions is ignored so CI/CD can freely update image tags
# without Terraform reverting them. To change container config (ports,
# health checks, etc.) temporarily set the lifecycle block to false,
# apply, then re-enable it.
#
# Internet Access & Cost:
# -----------------------
# Tasks in private subnets need a NAT Gateway (~$32/month) for:
#   - ECR image pulls (unless using VPC endpoint)
#   - Secrets Manager / SSM Parameter Store (unless using VPC endpoint)
#   - Any external API your Laravel app calls
################################################################################


################################################################################
# ECS Task Definition — nginx + php-fpm
################################################################################

resource "aws_ecs_task_definition" "task_definition" {
  family                   = var.task_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = var.cpu
  memory = var.memory

  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.task_role_arn

  # Ephemeral writable volumes when readonlyRootFilesystem = true.
  # nginx needs /tmp, /var/cache/nginx, /var/run.
  # php-fpm needs /tmp, /var/run (for pid files and temporary data).
  dynamic "volume" {
    for_each = var.enable_readonly_root_filesystem ? [
      { name = "nginx-tmp"   },
      { name = "nginx-cache" },
      { name = "nginx-run"   },
      { name = "php-tmp"     },
      { name = "php-run"     },
    ] : []
    content {
      name = volume.value.name
    }
  }

  container_definitions = jsonencode([

    # ── nginx container ──────────────────────────────────────────────────────
    # Reverse proxy that accepts traffic from the ALB and forwards to php-fpm.
    # Waits for php-fpm HEALTHY before starting (dependsOn).
    {
      name      = var.container_name_nginx
      image     = var.nginx_image
      essential = true

      readonlyRootFilesystem = var.enable_readonly_root_filesystem

      mountPoints = var.enable_readonly_root_filesystem ? [
        { sourceVolume = "nginx-tmp",   containerPath = "/tmp",             readOnly = false },
        { sourceVolume = "nginx-cache", containerPath = "/var/cache/nginx", readOnly = false },
        { sourceVolume = "nginx-run",   containerPath = "/var/run",         readOnly = false },
      ] : []

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      dependsOn = [
        {
          containerName = var.container_name_php_fpm
          condition     = "HEALTHY"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_task_log_group.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "${var.log_stream_prefix}/nginx"
        }
      }

      healthCheck = var.health_check_enabled ? {
        command     = ["CMD-SHELL", "curl -sf http://localhost:${var.container_port}${var.health_check_endpoint} || exit 1"]
        interval    = var.health_check_interval
        timeout     = var.health_check_timeout
        retries     = var.health_check_retries
        startPeriod = var.health_check_start_period
      } : null
    },

    # ── php-fpm container ────────────────────────────────────────────────────
    # The Laravel application. Runs php-fpm on port 9000.
    # nginx health check depends on this container being HEALTHY first.
    {
      name      = var.container_name_php_fpm
      image     = "${var.ecr_repository_url}:${var.image_tag}"
      essential = true

      readonlyRootFilesystem = var.enable_readonly_root_filesystem

      mountPoints = var.enable_readonly_root_filesystem ? [
        { sourceVolume = "php-tmp", containerPath = "/tmp",     readOnly = false },
        { sourceVolume = "php-run", containerPath = "/var/run", readOnly = false },
      ] : []

      # No portMappings — php-fpm is only reached by nginx via localhost:9000.

      secrets     = var.secrets
      environment = var.environment_variables

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_task_log_group.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "${var.log_stream_prefix}/php-fpm"
        }
      }

      # nginx depends on php-fpm HEALTHY, so this health check must always be
      # present and use a check that works inside the php-fpm container image.
      # The default uses pidof which is available in standard php:*-fpm images.
      # Override php_fpm_health_check_command if your image uses a different check.
      healthCheck = {
        command     = ["CMD-SHELL", var.php_fpm_health_check_command]
        interval    = var.health_check_interval
        timeout     = var.health_check_timeout
        retries     = var.health_check_retries
        startPeriod = var.health_check_start_period
      }
    }
  ])

  # Prevents Terraform from reverting image tags that CI/CD has updated.
  # See the module header comment for when to temporarily disable this.
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
