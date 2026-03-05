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
    #
    # When central_s3_bucket_name is provided, this reflects the external
    # bucket.  Local bucket attributes (arn, id, versioning, encryption) are
    # null because this module does not own the central bucket.
    # ──────────────────────────────────────────────────────────────────────
    bucket = {
      # Bucket name — always populated (local or central)
      name = local.effective_s3_bucket_name

      # ARN / ID — only available for locally-managed buckets
      arn = local.using_local_bucket ? aws_s3_bucket.config_logs[0].arn : null
      id  = local.using_local_bucket ? aws_s3_bucket.config_logs[0].id  : null

      # Indicates whether this is a locally-created bucket or an external one
      is_central_bucket    = !local.using_local_bucket
      central_bucket_owner = var.central_s3_bucket_account_id # null when using local bucket

      # Settings below are only relevant for the locally-managed bucket
      versioning = local.using_local_bucket ? var.enable_bucket_versioning : null
      encryption = local.using_local_bucket ? (var.kms_key_arn != null ? "KMS" : "AES256") : null
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
    # Only meaningful when using a locally-managed bucket.
    # ──────────────────────────────────────────────────────────────────────
    lifecycle = {
      enabled                 = local.using_local_bucket ? var.enable_lifecycle_policy : false  # Lifecycle policy enabled?
      glacier_transition_days = local.using_local_bucket ? var.glacier_transition_days : null   # Days before moving to Glacier
      log_expiration_days     = local.using_local_bucket ? var.log_expiration_days     : null   # Days before permanent deletion
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
      module_enabled        = true                                                              # Module is active
      recording_active      = aws_config_configuration_recorder_status.this[0].is_enabled      # Recorder running?
      notifications_active  = var.sns_topic_arn != null                                        # SNS notifications configured?
      cost_optimization     = local.using_local_bucket && var.enable_lifecycle_policy          # Lifecycle policy reducing costs?
      using_central_bucket  = !local.using_local_bucket                                        # Using cross-account central bucket?
    }
  } : null
}

