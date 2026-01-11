################################################################################
# AWS Config Module Outputs
#
# All outputs are consolidated into a single 'config' object for easier
# consumption and cleaner code organization.
#
# Usage:
#   module.aws_config.config.bucket.name
#   module.aws_config.config.recorder.is_enabled
#   module.aws_config.config.account.account_id
################################################################################

output "config" {
  description = "AWS Config resources and configuration details"
  value = var.enable_aws_config ? {
    # ──────────────────────────────────────────────────────────────────────
    # S3 Bucket - Configuration log storage
    # ──────────────────────────────────────────────────────────────────────
    bucket = {
      name       = aws_s3_bucket.config_logs[0].bucket       # S3 bucket name
      arn        = aws_s3_bucket.config_logs[0].arn          # S3 bucket ARN
      id         = aws_s3_bucket.config_logs[0].id           # S3 bucket ID
      versioning = var.enable_bucket_versioning              # Versioning enabled?
      encryption = var.kms_key_arn != null ? "KMS" : "AES256" # Encryption type
    }

    # ──────────────────────────────────────────────────────────────────────
    # Configuration Recorder - Records resource configurations
    # ──────────────────────────────────────────────────────────────────────
    recorder = {
      name                     = aws_config_configuration_recorder.this[0].name                # Recorder name
      role_arn                 = aws_config_configuration_recorder.this[0].role_arn            # IAM role ARN
      record_all_resources     = var.record_all_resources                                      # Recording all resources?
      include_global_resources = var.include_global_resources                                  # Including global resources (IAM, etc.)?
      resource_types           = var.record_all_resources ? [] : var.resource_types            # Specific resource types (if not all)
      is_enabled               = aws_config_configuration_recorder_status.this[0].is_enabled   # Recording active?
    }

    # ──────────────────────────────────────────────────────────────────────
    # Delivery Channel - Delivers configuration snapshots to S3/SNS
    # ──────────────────────────────────────────────────────────────────────
    delivery_channel = {
      name               = aws_config_delivery_channel.this[0].name           # Delivery channel name
      s3_bucket_name     = aws_config_delivery_channel.this[0].s3_bucket_name # S3 bucket for snapshots
      s3_key_prefix      = var.s3_key_prefix                                  # S3 key prefix (folder path)
      snapshot_frequency = var.snapshot_delivery_frequency                    # How often snapshots are delivered
      sns_topic_arn      = var.sns_topic_arn                                  # SNS topic for notifications (null if disabled)
    }

    # ──────────────────────────────────────────────────────────────────────
    # Lifecycle Policy - S3 cost optimization settings
    # ──────────────────────────────────────────────────────────────────────
    lifecycle = {
      enabled                 = var.enable_lifecycle_policy      # Lifecycle policy enabled?
      glacier_transition_days = var.glacier_transition_days      # Days before moving to Glacier
      log_expiration_days     = var.log_expiration_days          # Days before permanent deletion
    }

    # ──────────────────────────────────────────────────────────────────────
    # Account Information - AWS account and region
    # ──────────────────────────────────────────────────────────────────────
    account = {
      account_id = data.aws_caller_identity.current.account_id # AWS account ID
      region     = data.aws_region.current.name                # AWS region
    }

    # ──────────────────────────────────────────────────────────────────────
    # Configuration Summary - Quick reference for module status
    # ──────────────────────────────────────────────────────────────────────
    summary = {
      module_enabled       = true                                # Module is active
      recording_active     = aws_config_configuration_recorder_status.this[0].is_enabled
      notifications_active = var.sns_topic_arn != null           # SNS notifications configured?
      cost_optimization    = var.enable_lifecycle_policy         # Lifecycle policy reducing costs?
    }
  } : null
}


