################################################################################
# AWS Config Module Outputs
################################################################################

output "config" {
  description = "AWS Config resources and configuration details"
  value = var.enable_aws_config ? {
    # S3 Bucket
    bucket = {
      name = aws_s3_bucket.config_logs[0].bucket
      arn  = aws_s3_bucket.config_logs[0].arn
      id   = aws_s3_bucket.config_logs[0].id
    }

    # Configuration Recorder
    recorder = {
      name                     = aws_config_configuration_recorder.this[0].name
      role_arn                 = aws_config_configuration_recorder.this[0].role_arn
      record_all_resources     = var.record_all_resources
      include_global_resources = var.include_global_resources
      is_enabled               = aws_config_configuration_recorder_status.this[0].is_enabled
    }

    # Delivery Channel
    delivery_channel = {
      name               = aws_config_delivery_channel.this[0].name
      s3_bucket_name     = aws_config_delivery_channel.this[0].s3_bucket_name
      snapshot_frequency = var.snapshot_delivery_frequency
      sns_topic_arn      = var.sns_topic_arn
    }

    # Lifecycle Policy
    lifecycle = {
      enabled                  = var.enable_lifecycle_policy
      glacier_transition_days  = var.glacier_transition_days
      log_expiration_days      = var.log_expiration_days
    }

    # Account Info
    account = {
      account_id = data.aws_caller_identity.current.account_id
      region     = data.aws_region.current.name
    }
  } : null
}

# Individual outputs for easier reference

output "bucket_name" {
  description = "Name of the S3 bucket storing AWS Config logs"
  value       = var.enable_aws_config ? aws_s3_bucket.config_logs[0].bucket : null
}

output "bucket_arn" {
  description = "ARN of the S3 bucket storing AWS Config logs"
  value       = var.enable_aws_config ? aws_s3_bucket.config_logs[0].arn : null
}

output "recorder_name" {
  description = "Name of the AWS Config configuration recorder"
  value       = var.enable_aws_config ? aws_config_configuration_recorder.this[0].name : null
}

output "recorder_status" {
  description = "Status of the AWS Config configuration recorder (true = enabled)"
  value       = var.enable_aws_config ? aws_config_configuration_recorder_status.this[0].is_enabled : null
}

output "delivery_channel_name" {
  description = "Name of the AWS Config delivery channel"
  value       = var.enable_aws_config ? aws_config_delivery_channel.this[0].name : null
}

