################################################################################
# Laravel Web Task Definition - CloudWatch Log Group
#
# One log group per task. Both nginx and php-fpm stream into it using
# separate prefixes:  <prefix>/nginx  and  <prefix>/php-fpm
################################################################################

resource "aws_cloudwatch_log_group" "ecs_task_log_group" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days

  tags = merge(
    {
      Name      = var.log_group_name
      ManagedBy = "Terraform"
      Purpose   = "ECS Task Logs"
    },
    var.environment != "" ? { Environment = var.environment } : {},
    var.project_id != "" ? { Project = var.project_id } : {},
    var.tags
  )
}
