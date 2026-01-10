################################################################################
# Basic Node.js ECS Task Definition Module
#
# Purpose: Create a reusable ECS task definition for Node.js applications
#          running on AWS Fargate with CloudWatch logging and health checks.
#
# Components:
# - CloudWatch Log Group for container logs (optional)
# - ECS Task Definition with container specs
# - Support for secrets from SSM Parameter Store / Secrets Manager
# - Configurable health checks
# - Lifecycle management for CI/CD compatibility
#
# ⚠️ IMPORTANT - Configuration Updates & Container Restarts:
# ===========================================================
# When you update SSM parameters or Secrets Manager values, existing containers
# DO NOT automatically get the new values. You must force a restart.
#
# Why? Because secrets/parameters are injected ONLY at container STARTUP.
# Once running, containers use cached environment variables from startup time.
#
# How to Force Container Restart (Pick Up New Configs):
# ======================================================
#
# Method 1: Re-run GitHub Actions Workflow (EASIEST - Recommended) ⭐
# ------------------------------------------------------------------
# Since your deployment runs through GitHub Actions CI/CD:
#
# 1. Go to GitHub → Actions tab
# 2. Find the last successful workflow run
# 3. Click "Re-run all jobs" or "Re-run failed jobs"
#
# What happens:
# 1. GitHub Actions builds a new Docker image (same code, fresh build)
# 2. Pushes new image to ECR with new tag (commit SHA)
# 3. Updates ECS task definition with new image tag
# 4. ECS automatically starts rolling deployment
# 5. New tasks fetch LATEST values from SSM/Secrets Manager
# 6. ALB routes traffic to new tasks once healthy
# 7. Old tasks are drained and stopped
# 8. Zero downtime! ✅
#
# Time: 3-7 minutes (includes build time + deployment)
# Downtime: NONE
# Advantages:
# - ✅ No AWS CLI commands needed (just click in GitHub UI)
# - ✅ Consistent with normal deployment process
# - ✅ Full audit trail in GitHub Actions logs
# - ✅ Can be triggered from anywhere (even mobile)
# - ✅ Works even if you're not on your dev machine
#
# When to use: ALWAYS (after updating SSM/Secrets Manager values)
#
# Method 2: Force New Deployment via AWS CLI (Alternative)
# ---------------------------------------------------------
# If GitHub Actions is unavailable or you need immediate restart:
#
# aws ecs update-service \
#   --cluster YOUR-CLUSTER-NAME \
#   --service YOUR-SERVICE-NAME \
#   --force-new-deployment
#
# What happens:
# 1. ECS starts NEW tasks with current task definition (same image tag)
# 2. New tasks fetch LATEST values from SSM/Secrets Manager
# 3. ALB routes traffic to new tasks once healthy
# 4. Old tasks are drained and stopped
#
# Time: 2-5 minutes (faster than Method 1 - no build)
# Downtime: NONE
#
# Method 3: Stop Individual Tasks (Triggers Auto-Replacement)
# ------------------------------------------------------------
# aws ecs stop-task --cluster YOUR-CLUSTER --task <task-id>
# ECS will automatically start a new task with fresh configs.
#
# IMPORTANT - Internet Access & Cost Implications:
# ================================================
# Tasks in PRIVATE SUBNETS require OUTBOUND internet access for:
# - External services (Mailtrap, SendGrid, Twilio, payment gateways, etc.)
# - Third-party APIs (Google Maps, authentication providers, etc.)
# - Package registries (npm, if installing at runtime)
# - Webhooks and external callbacks
#
# Internet Access Strategy:
# -------------------------
# ✅ NAT Gateway (REQUIRED for external internet) - ~$32.40/month + data transfer
#    - Enables outbound connections to ANY internet service
#    - Mandatory if app needs external APIs, email services, webhooks, etc.
#
# ❌ VPC Endpoints (NOT sufficient for external services) - Would save ~$11/month
#    - Only works for AWS services (S3, ECR, CloudWatch, etc.)
#    - CANNOT reach external internet (Mailtrap, Stripe, etc.)
#    - Only use if app NEVER needs external internet access
#
# Cost Breakdown (Private Subnets + NAT Gateway):
# ------------------------------------------------
# - ECS Fargate (0.25 vCPU, 1 GB):     $12.23/month
# - NAT Gateway:                       $32.40/month (largest cost!)
# - NAT Data Transfer:                 $0.045/GB processed
# - ALB:                               $21.20/month
# - CloudWatch Logs:                   $2.50/month
# TOTAL:                               ~$68+/month
#
# Alternative (Public Subnets - NOT RECOMMENDED for production):
# --------------------------------------------------------------
# If cost is critical and security is less important, you could:
# - Move tasks to PUBLIC subnets (assign_public_ip = true)
# - Remove NAT Gateway (saves $32.40/month)
# - Total cost would be ~$37/month
# - BUT: Tasks would have public IPs and be internet-accessible (security risk!)
#
# Recommendation: Keep Private + NAT for production security.
################################################################################


################################################################################
# ECS Task Definition
################################################################################

resource "aws_ecs_task_definition" "task_definition" {
  family                   = var.task_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = var.cpu
  memory = var.memory

  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = "${var.ecr_repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = var.container_protocol
        }
      ]

      # Secrets from SSM Parameter Store or Secrets Manager
      # Values are fetched at container startup by the Task Execution Role
      secrets = var.secrets

      # Static environment variables
      environment = var.environment_variables

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_task_log_group[0].name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = var.log_stream_prefix
        }
      }

      # Health check configuration
      healthCheck = var.health_check_enabled ? {
        command = [
          "CMD-SHELL",
          "node -e \"require('http').get('http://localhost:${var.container_port}${var.health_check_endpoint}', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})\""
        ]
        interval    = var.health_check_interval
        timeout     = var.health_check_timeout
        retries     = var.health_check_retries
        startPeriod = var.health_check_start_period
      } : null
    }
  ])

  # Lifecycle rule to prevent Terraform from reverting image updates
  # When CI/CD updates the image tag (e.g., from 'abc123' to 'xyz789'),
  # Terraform will ignore this change and not revert to the default tag.
  #
  # Why ignore container_definitions entirely?
  # - container_definitions is a JSON string, not a structured object
  # - We can't use :: syntax to target just the image field
  # - Ignoring the entire block prevents Terraform from:
  #   * Reverting image tags updated by GitHub Actions
  #   * Overwriting environment variables added via AWS Console
  #   * Changing any container config modified outside Terraform
  #
  # Note: If you need to update container config (ports, health checks, etc.),
  #       temporarily set ignore_changes_to_container_definitions = false,
  #       apply changes, then set back to true.
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

