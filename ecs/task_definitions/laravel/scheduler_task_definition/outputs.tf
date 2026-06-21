################################################################################
# Laravel Scheduler ECS Task Definition - Outputs
#
# Usage:
#   module.laravel_scheduler_task.task.definition.arn
#   module.laravel_scheduler_task.task.container.name
#   module.laravel_scheduler_task.task.log_group.name
#
# The task ARN is what you pass to the EventBridge Scheduler as the target:
#   aws_scheduler_schedule → target → ecs_parameters → task_definition_arn
################################################################################

output "task" {
  description = "Complete ECS Task Definition and related resources"
  value = {
    definition = {
      arn      = aws_ecs_task_definition.task_definition.arn
      family   = aws_ecs_task_definition.task_definition.family
      revision = aws_ecs_task_definition.task_definition.revision

      # Pass this ARN to EventBridge Scheduler's ecs_parameters.task_definition_arn
      arn_with_revision = "${aws_ecs_task_definition.task_definition.family}:${aws_ecs_task_definition.task_definition.revision}"
    }

    container = {
      name    = var.container_name
      image   = "${var.ecr_repository_url}:${var.image_tag}"
      command = var.scheduler_command
    }

    resources = {
      cpu    = var.cpu
      memory = var.memory
    }

    log_group = {
      name = aws_cloudwatch_log_group.ecs_task_log_group.name
      arn  = aws_cloudwatch_log_group.ecs_task_log_group.arn
    }
  }
}
