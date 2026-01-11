################################################################################
# AWS Config - Continuous Configuration Monitoring
#
# Purpose: Enable AWS Config to continuously monitor and record AWS resource
#          configurations for compliance auditing and security analysis.
#
# Features:
# - Multi-region configuration recording
# - S3 bucket for configuration snapshots and history (see bucket.tf)
# - Optional SNS notifications for configuration changes
# - Support for AWS Config Rules (managed externally or via conformance packs)
#
# Components:
# 1. Configuration Recorder: Records resource configurations
# 2. Delivery Channel: Delivers configuration snapshots to S3 (and optionally SNS)
# 3. Recorder Status: Starts/stops the configuration recorder
#
# Prerequisites:
# - AWS Config service-linked role (created automatically on first use)
#   arn:aws:iam::ACCOUNT_ID:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig
# - S3 bucket for logs (configured in bucket.tf)
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
  sns_topic_arn  = var.sns_topic_arn

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

