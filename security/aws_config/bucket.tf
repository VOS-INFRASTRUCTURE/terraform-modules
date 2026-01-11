################################################################################
# AWS Config - S3 Bucket Configuration
#
# Purpose: S3 bucket for storing AWS Config configuration snapshots, history,
#          and compliance evaluation results.
#
# Features:
# - Public access blocked
# - Server-side encryption (AES256 or KMS)
# - Optional versioning for audit trail protection
# - Lifecycle policy for cost optimization (Glacier transition + expiration)
# - Bucket policy allowing AWS Config service to write logs
################################################################################

################################################################################
# S3 Bucket for AWS Config Logs
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

################################################################################
# S3 Bucket - Public Access Block
################################################################################

resource "aws_s3_bucket_public_access_block" "config_logs" {
  count  = var.enable_aws_config ? 1 : 0
  bucket = aws_s3_bucket.config_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

################################################################################
# S3 Bucket - Versioning
################################################################################

resource "aws_s3_bucket_versioning" "config_logs" {
  count  = var.enable_aws_config && var.enable_bucket_versioning ? 1 : 0
  bucket = aws_s3_bucket.config_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

################################################################################
# S3 Bucket - Server-Side Encryption
################################################################################

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

################################################################################
# S3 Bucket - Lifecycle Policy
#
# Cost Optimization:
# - Transition to Glacier after specified days (default: 90 days)
# - Expire logs after specified days (default: 2555 days / ~7 years)
################################################################################

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
# 2. List bucket contents (ListBucket)
# 3. Write configuration snapshots (PutObject)
#
# Note: The PutObject permission is scoped to:
#       s3://bucket-name/AWSLogs/<account-id>/*
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

