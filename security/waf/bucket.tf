################################################################################
# WAF Logs - S3 Bucket Configuration
#
# Purpose: S3 bucket for storing WAF logs with intelligent routing and
#          lifecycle management via Kinesis Firehose.
#
# Features:
# - Public access blocked
# - Server-side encryption (AES256)
# - Lifecycle policies for cost optimization:
#   - Blocked requests: 90 days (high value for investigation)
#   - Allowed requests: 7 days (low value)
#   - Errors: 7 days
# - Dynamic partitioning via Lambda (blocked/, allowed/, errors/)
################################################################################

################################################################################
# S3 Bucket for WAF Logs
################################################################################

resource "aws_s3_bucket" "cerpac_waf_logs" {
  count = var.enable_waf_logging ? 1 : 0

  bucket        = "${var.env}-${var.project_id}-${local.cerpac_frontend_alb_key_name}-waf-logs"
  force_destroy = var.force_destroy_log_bucket

  tags = merge(
    var.tags,
    {
      Name        = "${var.env}-${var.project_id}-waf-logs"
      Environment = var.env
      Project     = var.project_id
      Purpose     = "WAF-Logs"
      ManagedBy   = "Terraform"
    }
  )
}

################################################################################
# S3 Bucket - Public Access Block
################################################################################

resource "aws_s3_bucket_public_access_block" "cerpac_waf_logs" {
  count = var.enable_waf_logging ? 1 : 0

  bucket = aws_s3_bucket.cerpac_waf_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

################################################################################
# S3 Bucket - Server-Side Encryption
################################################################################

resource "aws_s3_bucket_server_side_encryption_configuration" "cerpac_waf_logs" {
  count = var.enable_waf_logging ? 1 : 0

  bucket = aws_s3_bucket.cerpac_waf_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

################################################################################
# S3 Bucket - Lifecycle Configuration
#
# Cost Optimization:
# - BLOCKED requests → 90 days (high value for security investigation)
# - ALLOWED requests → 7 days (low value, normal traffic)
# - ERRORS → 7 days (debugging only)
################################################################################

resource "aws_s3_bucket_lifecycle_configuration" "cerpac_waf_logs" {
  count = var.enable_waf_logging ? 1 : 0

  bucket = aws_s3_bucket.cerpac_waf_logs[0].id

  # BLOCKED requests → 90 days retention
  rule {
    id     = "blocked-logs-retention"
    status = "Enabled"

    filter {
      prefix = "blocked/"
    }

    expiration {
      days = var.blocked_logs_retention_days
    }
  }

  # ALLOWED requests → 7 days retention
  rule {
    id     = "allowed-logs-retention"
    status = "Enabled"

    filter {
      prefix = "allowed/"
    }

    expiration {
      days = var.allowed_logs_retention_days
    }
  }

  # ERROR logs → 7 days retention
  rule {
    id     = "errors-logs-retention"
    status = "Enabled"

    filter {
      prefix = "errors/"
    }

    expiration {
      days = var.error_logs_retention_days
    }
  }
}

