################################################################################
# Outputs
################################################################################

output "dynamodb" {
  description = "DynamoDB table configuration and connection details"
  value = {
    table = {
      id           = aws_dynamodb_table.this.id
      arn          = aws_dynamodb_table.this.arn
      name         = aws_dynamodb_table.this.name
      billing_mode = aws_dynamodb_table.this.billing_mode
      table_class  = aws_dynamodb_table.this.table_class
      hash_key     = aws_dynamodb_table.this.hash_key
      range_key    = aws_dynamodb_table.this.range_key
    }

    stream = var.enable_streams ? {
      enabled    = true
      arn        = aws_dynamodb_table.this.stream_arn
      label      = aws_dynamodb_table.this.stream_label
      view_type  = var.stream_view_type
    } : {
      enabled = false
    }

    recovery = {
      point_in_time_recovery = var.enable_point_in_time_recovery
      deletion_protection    = var.enable_deletion_protection
    }

    security = {
      encrypted   = var.enable_server_side_encryption
      kms_key_arn = var.kms_key_arn != "" ? var.kms_key_arn : "aws/dynamodb (default)"
    }

    autoscaling = {
      enabled = local.autoscaling_enabled
    }

    global_secondary_indexes = [for gsi in var.global_secondary_indexes : gsi.name]
    local_secondary_indexes  = [for lsi in var.local_secondary_indexes : lsi.name]
  }
}
