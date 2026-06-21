################################################################################
# Laravel Web ECS Task Definition - Outputs
#
# Usage:
#   module.laravel_web_task.task.definition.arn
#   module.laravel_web_task.task.container.nginx_name
#   module.laravel_web_task.task.container.php_fpm_name
#   module.laravel_web_task.task.log_group.name
################################################################################

output "task" {
  description = "Complete ECS Task Definition and related resources"
  value = {
    definition = {
      arn      = aws_ecs_task_definition.task_definition.arn
      family   = aws_ecs_task_definition.task_definition.family
      revision = aws_ecs_task_definition.task_definition.revision

      # Use this in an ECS service's task_definition field
      arn_with_revision = "${aws_ecs_task_definition.task_definition.family}:${aws_ecs_task_definition.task_definition.revision}"
    }

    container = {
      # nginx is the ALB target — bind the target group to this container name + port
      nginx_name = var.container_name_nginx
      nginx_port = var.container_port

      php_fpm_name = var.container_name_php_fpm
      php_fpm_port = 9000

      # Full image URIs (informational)
      nginx_image   = var.nginx_image
      php_fpm_image = "${var.ecr_repository_url}:${var.image_tag}"
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
