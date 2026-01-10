
################################################################################
# CloudWatch Log Group for ECS Task Logs
################################################################################

resource "aws_cloudwatch_log_group" "ecs_task_log_group" {
  count = var.create_log_group ? 1 : 0

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