################################################################################
# Laravel Horizon ECS Task Definition - Outputs
#
# Usage:
#   module.laravel_horizon_task.task.definition.arn
#   module.laravel_horizon_task.task.container.name
#   module.laravel_horizon_task.task.log_group.name
################################################################################

output "task" {
  description = "Complete ECS Task Definition and related resources"
  value = {
    definition = {
      arn      = aws_ecs_task_definition.task_definition.arn
      family   = aws_ecs_task_definition.task_definition.family
      revision = aws_ecs_task_definition.task_definition.revision

      # Use this in the ECS service's task_definition field
      arn_with_revision = "${aws_ecs_task_definition.task_definition.family}:${aws_ecs_task_definition.task_definition.revision}"
    }

    container = {
      name  = var.container_name
      image = "${var.ecr_repository_url}:${var.image_tag}"
    }

    resources = {
      cpu          = var.cpu
      memory       = var.memory
      stop_timeout = var.stop_timeout
    }

    log_group = {
      name = aws_cloudwatch_log_group.ecs_task_log_group.name
      arn  = aws_cloudwatch_log_group.ecs_task_log_group.arn
    }
  }
}
