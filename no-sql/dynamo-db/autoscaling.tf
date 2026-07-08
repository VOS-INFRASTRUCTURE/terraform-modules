################################################################################
# Application Auto Scaling for Provisioned Capacity
#
# Only created when billing_mode = PROVISIONED and enable_autoscaling = true.
# Manages the table's read/write capacity between the min/max bounds; the
# aws_dynamodb_table lifecycle.ignore_changes above stops terraform from
# fighting these adjustments on subsequent applies.
################################################################################

locals {
  autoscaling_enabled = local.is_provisioned && var.enable_autoscaling

  gsi_by_name = { for gsi in var.global_secondary_indexes : gsi.name => gsi }
}

# --- Table: Read ---

resource "aws_appautoscaling_target" "table_read" {
  count = local.autoscaling_enabled ? 1 : 0

  max_capacity       = var.autoscaling_read_max
  min_capacity       = var.autoscaling_read_min
  resource_id        = "table/${aws_dynamodb_table.this.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "table_read" {
  count = local.autoscaling_enabled ? 1 : 0

  name               = "${local.table_name}-read-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.table_read[0].resource_id
  scalable_dimension  = aws_appautoscaling_target.table_read[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.table_read[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value = var.autoscaling_target_utilization
  }
}

# --- Table: Write ---

resource "aws_appautoscaling_target" "table_write" {
  count = local.autoscaling_enabled ? 1 : 0

  max_capacity       = var.autoscaling_write_max
  min_capacity       = var.autoscaling_write_min
  resource_id        = "table/${aws_dynamodb_table.this.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "table_write" {
  count = local.autoscaling_enabled ? 1 : 0

  name               = "${local.table_name}-write-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.table_write[0].resource_id
  scalable_dimension  = aws_appautoscaling_target.table_write[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.table_write[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    target_value = var.autoscaling_target_utilization
  }
}

# --- GSIs: Read ---

resource "aws_appautoscaling_target" "gsi_read" {
  for_each = local.autoscaling_enabled ? local.gsi_by_name : {}

  max_capacity       = var.autoscaling_read_max
  min_capacity       = var.autoscaling_read_min
  resource_id        = "table/${aws_dynamodb_table.this.name}/index/${each.value.name}"
  scalable_dimension = "dynamodb:index:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "gsi_read" {
  for_each = local.autoscaling_enabled ? local.gsi_by_name : {}

  name               = "${local.table_name}-${each.value.name}-read-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.gsi_read[each.key].resource_id
  scalable_dimension  = aws_appautoscaling_target.gsi_read[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.gsi_read[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value = var.autoscaling_target_utilization
  }
}

# --- GSIs: Write ---

resource "aws_appautoscaling_target" "gsi_write" {
  for_each = local.autoscaling_enabled ? local.gsi_by_name : {}

  max_capacity       = var.autoscaling_write_max
  min_capacity       = var.autoscaling_write_min
  resource_id        = "table/${aws_dynamodb_table.this.name}/index/${each.value.name}"
  scalable_dimension = "dynamodb:index:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "gsi_write" {
  for_each = local.autoscaling_enabled ? local.gsi_by_name : {}

  name               = "${local.table_name}-${each.value.name}-write-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.gsi_write[each.key].resource_id
  scalable_dimension  = aws_appautoscaling_target.gsi_write[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.gsi_write[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    target_value = var.autoscaling_target_utilization
  }
}
