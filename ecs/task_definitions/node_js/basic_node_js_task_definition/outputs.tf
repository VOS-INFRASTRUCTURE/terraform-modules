################################################################################
# Basic Node.js ECS Task Definition - Outputs
#
# Purpose: Export task definition and log group details for use in ECS services
#
# Usage:
#   module.node_app_task.task.definition.arn
#   module.node_app_task.task.definition.family
#   module.node_app_task.task.container.name
#   module.node_app_task.task.log_group.name
################################################################################

output "task" {
  description = "Complete ECS Task Definition and related resources"
  value = {
    # Task Definition Details
    definition = {
      arn      = aws_ecs_task_definition.task_definition.arn               # ARN without revision
      family   = aws_ecs_task_definition.task_definition.family            # Task definition family name
      revision = aws_ecs_task_definition.task_definition.revision          # Current revision number

      # Full ARN with revision (use this in ECS service configuration)
      arn_with_revision = "${aws_ecs_task_definition.task_definition.family}:${aws_ecs_task_definition.task_definition.revision}"
    }

    # Container Configuration
    container = {
      name  = var.container_name                                           # Container name for target group binding
      port  = var.container_port                                           # Exposed container port
      image = "${var.ecr_repository_url}:${var.image_tag}"                # Full container image URL with tag
    }

    # Resource Allocation
    resources = {
      cpu    = var.cpu                                                     # CPU units (256 = 0.25 vCPU)
      memory = var.memory                                                  # Memory in MiB
    }

    # CloudWatch Logging
    log_group = var.create_log_group ? {
      name = aws_cloudwatch_log_group.ecs_task_log_group[0].name          # Log group name
      arn  = aws_cloudwatch_log_group.ecs_task_log_group[0].arn           # Log group ARN
    } : {
      name = var.log_group_name                                            # External log group name
      arn  = null                                                          # No ARN (managed externally)
    }
  }
}

