################################################################################
# DynamoDB Table
#
# Defaults follow docs/CostComparison.md's recommendation: start on-demand
# (PAY_PER_REQUEST), Standard table class, PITR on. Switch to PROVISIONED
# (+ enable_autoscaling) once CloudWatch shows steady, predictable traffic.
#
# The hash_key/range_key primary key is the one setting here that cannot be
# changed after creation — see docs/Analysis.md and docs/Glossary.md.
################################################################################

locals {
  table_name = var.table_name != "" ? var.table_name : "${var.project_id}-${var.env}-${var.base_name}"

  is_provisioned = var.billing_mode == "PROVISIONED"
}

resource "aws_dynamodb_table" "this" {
  name         = local.table_name
  billing_mode = var.billing_mode
  table_class  = var.table_class

  hash_key  = var.hash_key
  range_key = var.range_key != "" ? var.range_key : null

  read_capacity  = local.is_provisioned ? var.read_capacity : null
  write_capacity = local.is_provisioned ? var.write_capacity : null

  attribute {
    name = var.hash_key
    type = var.hash_key_type
  }

  dynamic "attribute" {
    for_each = var.range_key != "" ? [{ name = var.range_key, type = var.range_key_type }] : []
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "attribute" {
    for_each = var.additional_attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  # Using hash_key/range_key here (not the newer key_schema block) deliberately:
  # key_schema currently has open provider bugs causing perpetual drift and
  # destructive GSI recreation (hashicorp/terraform-provider-aws#46601/#46335).
  dynamic "global_secondary_index" {
    for_each = var.global_secondary_indexes
    content {
      name               = global_secondary_index.value.name
      hash_key           = global_secondary_index.value.hash_key
      range_key          = global_secondary_index.value.range_key
      projection_type    = global_secondary_index.value.projection_type
      non_key_attributes = global_secondary_index.value.non_key_attributes
      read_capacity       = local.is_provisioned ? coalesce(global_secondary_index.value.read_capacity, var.read_capacity) : null
      write_capacity       = local.is_provisioned ? coalesce(global_secondary_index.value.write_capacity, var.write_capacity) : null
    }
  }

  dynamic "local_secondary_index" {
    for_each = var.local_secondary_indexes
    content {
      name               = local_secondary_index.value.name
      range_key          = local_secondary_index.value.range_key
      projection_type    = local_secondary_index.value.projection_type
      non_key_attributes = local_secondary_index.value.non_key_attributes
    }
  }

  dynamic "ttl" {
    for_each = var.enable_ttl ? [1] : []
    content {
      enabled        = true
      attribute_name = var.ttl_attribute_name
    }
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled     = var.enable_server_side_encryption
    kms_key_arn = var.kms_key_arn != "" ? var.kms_key_arn : null
  }

  stream_enabled   = var.enable_streams
  stream_view_type = var.enable_streams ? var.stream_view_type : null

  deletion_protection_enabled = var.enable_deletion_protection

  tags = merge(
    var.tags,
    {
      Name        = local.table_name
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
    }
  )

  lifecycle {
    # Once autoscaling manages capacity, terraform's own read/write_capacity
    # values would otherwise fight the aws_appautoscaling_policy on every apply.
    # Without autoscaling, capacity stays fully terraform-managed via the variables.
    ignore_changes = var.enable_autoscaling ? [read_capacity, write_capacity] : []
  }
}
