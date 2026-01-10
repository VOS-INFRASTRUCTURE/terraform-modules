################################################################################
# Basic Node.js ECS Task Definition - Outputs
#
# Purpose: Export task definition and log group details for use in ECS services
################################################################################

output "task_definition" {
  description = "Complete ECS Task Definition details"
  value = {
    arn      = aws_ecs_task_definition.task_definition.arn
    family   = aws_ecs_task_definition.task_definition.family
    revision = aws_ecs_task_definition.task_definition.revision

    # Full ARN with revision number (use this in ECS service)
    arn_with_revision = "${aws_ecs_task_definition.task_definition.family}:${aws_ecs_task_definition.task_definition.revision}"
  }
}

output "task_definition_arn" {
  description = "ARN of the ECS task definition (without revision)"
  value       = aws_ecs_task_definition.task_definition.arn
}

output "task_definition_family" {
  description = "Family name of the ECS task definition"
  value       = aws_ecs_task_definition.task_definition.family
}

output "task_definition_revision" {
  description = "Revision number of the ECS task definition"
  value       = aws_ecs_task_definition.task_definition.revision
}

output "log_group" {
  description = "CloudWatch Log Group details (if created)"
  value = var.create_log_group ? {
    name = aws_cloudwatch_log_group.ecs_task_log_group[0].name
    arn  = aws_cloudwatch_log_group.ecs_task_log_group[0].arn
  } : null
}

output "log_group_name" {
  description = "Name of the CloudWatch Log Group"
  value       = var.create_log_group ? aws_cloudwatch_log_group.ecs_task_log_group[0].name : var.log_group_name
}

output "container_name" {
  description = "Name of the container defined in the task definition"
  value       = var.container_name
}

output "container_port" {
  description = "Port that the container exposes"
  value       = var.container_port
}

output "container_image" {
  description = "Full container image URL with tag"
  value       = "${var.ecr_repository_url}:${var.image_tag}"
}

output "cpu" {
  description = "CPU units allocated to the task"
  value       = var.cpu
}

output "memory" {
  description = "Memory (MiB) allocated to the task"
  value       = var.memory
}

