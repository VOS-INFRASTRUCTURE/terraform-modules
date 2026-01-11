################################################################################
# AWS Config - Continuous Configuration Monitoring
#
# Purpose: Enable AWS Config to continuously monitor and record AWS resource
#          configurations for compliance auditing and security analysis.
#
# Features:
# - Multi-region configuration recording
# - S3 bucket for configuration snapshots and history
# - Optional SNS notifications for configuration changes
# - Support for AWS Config Rules (managed externally or via conformance packs)
#
# Components:
# 1. S3 Bucket: Stores configuration snapshots and change history
# 2. Configuration Recorder: Records resource configurations
# 3. Delivery Channel: Delivers configuration snapshots to S3 (and optionally SNS)
#
# Prerequisites:
# - AWS Config service-linked role (created automatically on first use)
#   arn:aws:iam::ACCOUNT_ID:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig
#
# Cost Impact:
# - Configuration Items: ~$0.003 per item recorded
# - Config Rule Evaluations: ~$0.001 per evaluation
# - S3 Storage: ~$0.023/GB/month
# - Typical production cost: $100-150/month
################################################################################

################################################################################
# Data Sources
################################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

################################################################################
# S3 Bucket for AWS Config Logs
#
# Purpose: Store configuration snapshots, configuration history, and compliance
#          evaluation results.
#
# Security:
# - Public access blocked
# - Server-side encryption (AES256)
# - Bucket policy restricts access to AWS Config service only
# - Versioning recommended (enable via lifecycle management)
################################################################################

resource "aws_s3_bucket" "config_logs" {
  count = var.enable_aws_config ? 1 : 0

  bucket        = "${var.env}-${var.project_id}-aws-config-logs"
  force_destroy = var.force_destroy_bucket

  tags = merge(
    var.tags,
    {
      Name        = "${var.env}-${var.project_id}-aws-config-logs"
      Environment = var.env
      Project     = var.project_id
      Purpose     = "AWS Config audit logs"
      Compliance  = "Required"
      ManagedBy   = "Terraform"
    }
  )
}

resource "aws_s3_bucket_public_access_block" "config_logs" {
  count  = var.enable_aws_config ? 1 : 0
  bucket = aws_s3_bucket.config_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "config_logs" {
  count  = var.enable_aws_config && var.enable_bucket_versioning ? 1 : 0
  bucket = aws_s3_bucket.config_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_logs" {
  count  = var.enable_aws_config ? 1 : 0
  bucket = aws_s3_bucket.config_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "config_logs" {
  count  = var.enable_aws_config && var.enable_lifecycle_policy ? 1 : 0
  bucket = aws_s3_bucket.config_logs[0].id

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    transition {
      days          = var.glacier_transition_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.log_expiration_days
    }
  }
}

################################################################################
# S3 Bucket Policy - Allow AWS Config to Write
#
# Grants AWS Config service permission to:
# 1. Check bucket ACL (GetBucketAcl)
# 2. Write configuration snapshots (PutObject)
################################################################################

resource "aws_s3_bucket_policy" "config_logs" {
  count  = var.enable_aws_config ? 1 : 0
  bucket = aws_s3_bucket.config_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config_logs[0].arn
      },
      {
        Sid    = "AWSConfigBucketExistenceCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.config_logs[0].arn
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config_logs[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

################################################################################
# Configuration Recorder
#
# Records configuration changes for specified AWS resources.
#
# Recording Options:
# - All supported resources (all_supported = true)
# - Include global resources (IAM, etc.) - only enable in one region
# - Specific resource types (via resource_types variable)
#
# Note: The service-linked role is created automatically by AWS when you
#       first enable AWS Config in your account.
################################################################################

resource "aws_config_configuration_recorder" "this" {
  count = var.enable_aws_config ? 1 : 0

  name     = "${var.env}-${var.project_id}-config-recorder"
  role_arn = var.config_role_arn != null ? var.config_role_arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"

  recording_group {
    all_supported                 = var.record_all_resources
    include_global_resource_types = var.include_global_resources
    resource_types                = var.record_all_resources ? [] : var.resource_types
  }

  # Note: AWS Config configuration recorder does not support tags directly
}

################################################################################
# Delivery Channel
#
# Defines where AWS Config delivers configuration snapshots and notifications.
#
# Outputs:
# - S3 bucket: Configuration snapshots and history (always)
# - SNS topic: Real-time notifications (optional)
#
# Snapshot Frequency:
# - One_Hour, Three_Hours, Six_Hours, Twelve_Hours, TwentyFour_Hours
################################################################################

resource "aws_config_delivery_channel" "this" {
  count = var.enable_aws_config ? 1 : 0

  name           = "${var.env}-${var.project_id}-config-delivery"
  s3_bucket_name = aws_s3_bucket.config_logs[0].bucket
  s3_key_prefix  = var.s3_key_prefix

  # Optional SNS notifications
  dynamic "sns_topic_arn" {
    for_each = var.sns_topic_arn != null ? [1] : []
    content {
      sns_topic_arn = var.sns_topic_arn
    }
  }

  snapshot_delivery_properties {
    delivery_frequency = var.snapshot_delivery_frequency
  }

  depends_on = [
    aws_config_configuration_recorder.this,
    aws_s3_bucket_policy.config_logs
  ]
}

################################################################################
# Start Configuration Recorder
#
# Enables the configuration recorder to start recording.
#
# IMPORTANT: This must be created AFTER the delivery channel is configured,
#            otherwise AWS Config will fail to start.
################################################################################

resource "aws_config_configuration_recorder_status" "this" {
  count = var.enable_aws_config ? 1 : 0

  name       = aws_config_configuration_recorder.this[0].name
  is_enabled = true

  depends_on = [
    aws_config_delivery_channel.this
  ]
}

