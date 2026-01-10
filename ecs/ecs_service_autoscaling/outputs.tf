################################################################################
# ECS Service Autoscaling Module - Outputs
#
# Purpose: Export autoscaling configuration and policy details
#
# Usage:
#   module.autoscaling.scaling.target.min_capacity
#   module.autoscaling.scaling.policies.cpu.target_value
################################################################################

output "scaling" {
  description = "Complete ECS autoscaling configuration and policies"
  value = {
    # Auto Scaling Target
    target = {
      resource_id       = aws_appautoscaling_target.ecs_target.resource_id      # Full resource ID
      min_capacity      = aws_appautoscaling_target.ecs_target.min_capacity     # Minimum tasks
      max_capacity      = aws_appautoscaling_target.ecs_target.max_capacity     # Maximum tasks
      service_namespace = aws_appautoscaling_target.ecs_target.service_namespace # Service namespace
    }

    # Scaling Policies
    policies = {
      # CPU-Based Scaling
      cpu = var.enable_cpu_scaling ? {
        enabled            = true
        name               = aws_appautoscaling_policy.cpu_policy[0].name
        policy_type        = aws_appautoscaling_policy.cpu_policy[0].policy_type
        target_value       = var.cpu_target_value
        scale_in_cooldown  = var.cpu_scale_in_cooldown
        scale_out_cooldown = var.cpu_scale_out_cooldown
      } : {
        enabled = false
      }

      # Memory-Based Scaling
      memory = var.enable_memory_scaling ? {
        enabled            = true
        name               = aws_appautoscaling_policy.memory_policy[0].name
        policy_type        = aws_appautoscaling_policy.memory_policy[0].policy_type
        target_value       = var.memory_target_value
        scale_in_cooldown  = var.memory_scale_in_cooldown
        scale_out_cooldown = var.memory_scale_out_cooldown
      } : {
        enabled = false
      }

      # Request Count-Based Scaling
      request_count = var.enable_request_count_scaling ? {
        enabled            = true
        name               = aws_appautoscaling_policy.request_count_policy[0].name
        policy_type        = aws_appautoscaling_policy.request_count_policy[0].policy_type
        target_value       = var.request_count_target_value
        scale_in_cooldown  = var.request_count_scale_in_cooldown
        scale_out_cooldown = var.request_count_scale_out_cooldown
      } : {
        enabled = false
      }
    }

    # Scheduled Actions
    scheduled_actions = var.enable_scheduled_scaling ? {
      enabled = true
      count   = length(var.scheduled_actions)
      actions = var.scheduled_actions
    } : {
      enabled = false
    }

    # CloudWatch Alarms
    alarms = var.enable_scaling_alarms ? {
      enabled                = true
      max_capacity_alarm_arn = aws_cloudwatch_metric_alarm.max_capacity_alarm[0].arn
      min_capacity_alarm_arn = aws_cloudwatch_metric_alarm.min_capacity_alarm[0].arn
    } : {
      enabled = false
    }
  }
}

