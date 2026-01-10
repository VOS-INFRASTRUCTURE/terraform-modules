################################################################################
# Staging – ECS Task Definition for Node.js App
#
# Purpose: Define the container configuration, resources, and runtime settings
#          for the Node.js application running on ECS Fargate.
#
# Components:
# - CloudWatch Log Group for container logs
# - ECS Task Definition with container specs
# - References: ECR repo, execution role, network mode (awsvpc)
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
# =====================================================
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
#   --cluster staging-ecs-node-app-cluster \
#   --service staging-ecs-node-app-service \
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
# Disadvantages:
# - ❌ Requires AWS CLI access
# - ❌ Less visible audit trail
# - ❌ Same image tag (doesn't increment version)
#
# When to use: Emergency config updates, local testing
#
# Method 2: Stop Individual Tasks (Triggers Auto-Replacement)
# ------------------------------------------------------------
# # List running tasks
# aws ecs list-tasks \
#   --cluster staging-ecs-node-app-cluster \
#   --service-name staging-ecs-node-app-service
#
# # Stop a specific task (ECS auto-starts a new one)
# aws ecs stop-task \
#   --cluster staging-ecs-node-app-cluster \
#   --task <task-id>
#
# What happens:
# 1. You stop one task manually
# 2. ECS immediately starts a NEW task (desired count enforcement)
# 3. New task fetches latest configs
# 4. ALB routes traffic to new task
# 5. Repeat for other tasks if needed
#
# Time: 1-3 minutes per task
# Downtime: Brief (if only 1 task running); none if multiple tasks
#
# Method 3: Scale Down Then Up
# -----------------------------
# # Scale to 0 (stops all tasks)
# aws ecs update-service \
#   --cluster staging-ecs-node-app-cluster \
#   --service staging-ecs-node-app-service \
#   --desired-count 0
#
# # Wait for tasks to stop (~30 seconds)
# sleep 30
#
# # Scale back up
# aws ecs update-service \
#   --cluster staging-ecs-node-app-cluster \
#   --service staging-ecs-node-app-service \
#   --desired-count 1
#
# What happens:
# 1. All tasks stopped
# 2. SERVICE IS DOWN! ❌
# 3. New tasks start with latest configs
#
# Time: 1-2 minutes
# Downtime: YES! (30-60 seconds) - NOT RECOMMENDED for production
#
# Method 4: Update Task Definition Revision (Forces Recreation)
# --------------------------------------------------------------
# # Create new task definition revision (even with same config)
# aws ecs register-task-definition \
#   --cli-input-json file://task-definition.json
#
# # Update service to use new revision
# aws ecs update-service \
#   --cluster staging-ecs-node-app-cluster \
#   --service staging-ecs-node-app-service \
#   --task-definition staging-ecs-node-app-task:NEW_REVISION
#
# What happens:
# 1. New task definition revision created
# 2. Service switches to new revision
# 3. Rolling deployment starts (same as Method 1)
#
# Time: 2-5 minutes
# Downtime: NONE
#
# Method 5: Via Terraform (Automated on Infrastructure Changes)
# --------------------------------------------------------------
# If you comment out the lifecycle block below and run terraform apply,
# Terraform will detect changes and trigger a new task definition revision,
# which automatically forces a rolling deployment.
#
# # Temporarily comment this out:
# # lifecycle {
# #   ignore_changes = [container_definitions]
# # }
#
# terraform apply
#
# Time: 2-5 minutes
# Downtime: NONE
#
# When to Use Each Method:
# ========================
# - SSM parameter changed → Method 1 (re-run GitHub Actions) ⭐ EASIEST
# - Secret rotated → Method 1 (re-run GitHub Actions) ⭐ EASIEST
# - Config updated and need immediate pickup → Method 2 (force-new-deployment via CLI)
# - New Docker image pushed → GitHub Actions auto-deploys
# - Emergency rollback → AWS CLI (revert to previous task definition revision)
# - Testing/development → AWS CLI (stop individual tasks)
#
# IMPORTANT - Internet Access & Cost Implications:
# ===============================================
# This task runs in PRIVATE SUBNETS and requires OUTBOUND internet access for:
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
# -----------------------------------------------
# - ECS Fargate (0.25 vCPU, 1 GB):     $12.23/month
# - NAT Gateway:                       $32.40/month (largest cost!)
# - NAT Data Transfer:                 $0.045/GB processed
# - ALB:                               $21.20/month
# - CloudWatch Logs:                   $2.50/month
# - Other:                             $1.10/month
# TOTAL:                               ~$69.43/month
#
# Alternative (Public Subnets - NOT RECOMMENDED for production):
# --------------------------------------------------------------
# If cost is critical and security is less important, you could:
# - Move tasks to PUBLIC subnets (assign_public_ip = true)
# - Remove NAT Gateway (saves $32.40/month)
# - Total cost would be ~$37/month
# - BUT: Tasks would have public IPs and be internet-accessible (security risk!)
#
# Recommendation: Keep current setup (Private + NAT) for production security.
################################################################################

################################################################################
# CloudWatch Log Group for ECS Task Logs
################################################################################

resource "aws_cloudwatch_log_group" "ecs_task_log_group" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days

  tags = merge(
    {
      Name        = var.log_group_name
      ManagedBy   = "Terraform"
      Purpose     = "ECS Task Logs"
    },
      var.environment != "" ? { Environment = var.environment } : {},
      var.project_id != "" ? { Project = var.project_id } : {},
    var.tags
  )
}