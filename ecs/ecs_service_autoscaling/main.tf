################################################################################
# ECS Service Autoscaling Module
#
# Purpose: Automatically scale ECS tasks based on CPU, memory, or request count
#          to handle varying traffic loads while optimizing costs.
#
# Scaling Strategy:
# - Target Tracking: Automatically maintains target CPU/memory/request metrics
# - Scale-out: Fast response to traffic spikes (default: 60s cooldown)
# - Scale-in: Slow and conservative (default: 300s cooldown to prevent flapping)
#
# How it works:
# 1. CloudWatch monitors ECS service metrics (CPU, memory, requests)
# 2. When metric exceeds target, autoscaling adds tasks (after scale-out cooldown)
# 3. When metric falls below target, autoscaling removes tasks (after scale-in cooldown)
# 4. Never goes below min_capacity or above max_capacity
#
# Cost Impact:
# - More tasks during high load = higher cost (more vCPU/memory)
# - Fewer tasks during low load = lower cost
# - Typical savings: 30-50% vs fixed capacity (depends on traffic pattern)
#
# Prerequisites:
# - ECS service must have: lifecycle { ignore_changes = [desired_count] }
# - Container Insights enabled for better metrics visibility
################################################################################

locals {
  common_tags = merge(
    {
      Name      = var.ecs_service_name
      ManagedBy = "Terraform"
      Purpose   = "ECS-AutoScaling"
    },
    var.environment != "" ? { Environment = var.environment } : {},
    var.project_id != "" ? { Project = var.project_id } : {},
    var.tags
  )
}

################################################################################
# Auto Scaling Target
#
# Defines the ECS service to scale and min/max capacity limits.
################################################################################

resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${var.cluster_name}/${var.ecs_service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  tags = local.common_tags
}

################################################################################
# CPU-Based Scaling Policy (Target Tracking)
#
# Automatically scales tasks to maintain target CPU utilization.
# This is the primary scaling mechanism - recommended for most applications.
#
# Behavior:
# - CPU rises above target → Add tasks (scale out)
# - CPU falls below target → Remove tasks (scale in)
# - Auto Scaling calculates optimal task count to maintain target
################################################################################

resource "aws_appautoscaling_policy" "cpu_policy" {
  count = var.enable_cpu_scaling ? 1 : 0

  name               = "${var.ecs_service_name}-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target_value
    scale_in_cooldown  = var.cpu_scale_in_cooldown
    scale_out_cooldown = var.cpu_scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

################################################################################
# Memory-Based Scaling Policy (Target Tracking)
#
# Scales based on memory utilization. Works alongside CPU policy.
# When using multiple policies, auto scaling will scale based on whichever
# metric triggers first (most conservative approach).
#
# Use this if:
# - Your app is memory-intensive (caching, data processing)
# - Memory usage patterns differ from CPU usage
# - You want redundant scaling triggers for reliability
################################################################################

resource "aws_appautoscaling_policy" "memory_policy" {
  count = var.enable_memory_scaling ? 1 : 0

  name               = "${var.ecs_service_name}-memory-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.memory_target_value
    scale_in_cooldown  = var.memory_scale_in_cooldown
    scale_out_cooldown = var.memory_scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

################################################################################
# ALB Request Count Scaling Policy
#
# Scale based on incoming HTTP requests rather than resource utilization.
# This can be more responsive to traffic changes than CPU/memory metrics.
#
# Use this if:
# - You want to scale proactively based on request volume
# - Your app has consistent resource usage per request
# - You want tighter control over requests per task
#
# Formula: target_value = (max requests per task per minute)
# Example: If each task can handle 1000 req/min, set target_value = 1000
################################################################################

resource "aws_appautoscaling_policy" "request_count_policy" {
  count = var.enable_request_count_scaling ? 1 : 0

  name               = "${var.ecs_service_name}-request-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.request_count_target_value
    scale_in_cooldown  = var.request_count_scale_in_cooldown
    scale_out_cooldown = var.request_count_scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${var.alb_arn_suffix}/${var.target_group_arn_suffix}"
    }
  }
}

################################################################################
# Scheduled Scaling Actions
#
# Scale to specific task counts at specific times for predictable workloads.
# Useful for business hours, batch processing, or known traffic patterns.
#
# Example: Scale up for business hours (8 AM - 6 PM weekdays)
################################################################################

resource "aws_appautoscaling_scheduled_action" "scheduled_actions" {
  count = var.enable_scheduled_scaling ? length(var.scheduled_actions) : 0

  name               = var.scheduled_actions[count.index].name
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  schedule           = var.scheduled_actions[count.index].schedule

  scalable_target_action {
    min_capacity = var.scheduled_actions[count.index].min_capacity
    max_capacity = var.scheduled_actions[count.index].max_capacity
  }
}

################################################################################
# CloudWatch Alarm - Max Capacity Reached
#
# Alert when auto scaling hits the maximum capacity limit.
# This indicates you may need to increase max_capacity or investigate issues.
################################################################################

resource "aws_cloudwatch_metric_alarm" "max_capacity_alarm" {
  count = var.enable_scaling_alarms ? 1 : 0

  alarm_name          = "${var.ecs_service_name}-max-capacity-reached"
  alarm_description   = "Alert when ECS service reaches maximum task count (${var.max_capacity})"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "DesiredTaskCount"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = var.max_capacity

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = local.common_tags
}

################################################################################
# CloudWatch Alarm - Min Capacity Reached
#
# Alert when auto scaling is at minimum capacity but still under load.
# This may indicate min_capacity is too low.
################################################################################

resource "aws_cloudwatch_metric_alarm" "min_capacity_alarm" {
  count = var.enable_scaling_alarms ? 1 : 0

  alarm_name          = "${var.ecs_service_name}-min-capacity-high-cpu"
  alarm_description   = "Alert when at minimum capacity (${var.min_capacity}) but CPU is high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 85

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = local.common_tags
}

