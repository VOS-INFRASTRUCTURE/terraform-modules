################################################################################
# CloudTrail - S3 Bucket Configuration
#
# Purpose: S3 bucket for storing CloudTrail audit logs with secure access,
#          encryption, versioning, and lifecycle management.
#
# NOTE: All resources in this file are skipped when central_s3_bucket_name
#       is provided. In that case the trail writes directly to the central
#       bucket which must already carry the appropriate bucket policy.
#
# Features:
# - Public access blocked
# - Server-side encryption (AES256)
# - Versioning enabled for audit trail protection
# - Lifecycle policy for log retention
# - Bucket policy allowing CloudTrail service to write logs
################################################################################

################################################################################
# S3 Bucket for CloudTrail Logs
################################################################################

resource "aws_s3_bucket" "cloudtrail_logs" {
  # Skip when a central bucket is provided — nothing to create locally.
  count = var.central_s3_bucket_name == null ? 1 : 0

  bucket        = local.ct_bucket_name
  force_destroy = var.force_destroy

  tags = {
    Name        = "${var.env}-${var.project_id}-cloudtrail-logs"
    Environment = var.env
    Project     = var.project_id
    Purpose     = "CloudTrailAuditLogs"
    Compliance  = "Required"
    ManagedBy   = "Terraform"
  }
}

################################################################################
# S3 Bucket - Public Access Block
################################################################################

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  count  = var.central_s3_bucket_name == null ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

################################################################################
# S3 Bucket - Server-Side Encryption
################################################################################

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  count  = var.central_s3_bucket_name == null ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

################################################################################
# S3 Bucket - Versioning
#
# Versioning provides additional protection for audit logs by maintaining
# multiple versions of objects. This is useful for:
# - Recovering from accidental deletions
# - Preventing malicious log tampering
# - Meeting compliance requirements
#
# Note: Versioning increases storage costs as old versions are retained
################################################################################

resource "aws_s3_bucket_versioning" "cloudtrail" {
  count  = var.central_s3_bucket_name == null && var.enable_bucket_versioning ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

################################################################################
# S3 Bucket - Lifecycle Policy
#
# Retention Management:
# - Expire logs after specified retention period
# - Expire old versions after retention period
################################################################################

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  count  = var.central_s3_bucket_name == null ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  rule {
    id     = "cloudtrail-retention"
    status = "Enabled"

    expiration {
      days = var.retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.retention_days
    }
  }
}

################################################################################
# S3 Bucket Policy - Allow CloudTrail to Write
#
# Grants CloudTrail service permission to:
# 1. Check bucket ACL (GetBucketAcl)
# 2. Write audit logs (PutObject)
#
# Security: Only CloudTrail service can write to this bucket
################################################################################

resource "aws_s3_bucket_policy" "cloudtrail" {
  count  = var.central_s3_bucket_name == null ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs[0].arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}
