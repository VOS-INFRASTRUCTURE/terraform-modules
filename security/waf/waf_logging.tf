resource "aws_s3_bucket" "cerpac_waf_logs" {
  bucket = "${var.env}-cerpac-${local.cerpac_frontend_alb_key_name}-waf-logs"

  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "cerpac_waf_logs" {
  bucket = aws_s3_bucket.cerpac_waf_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cerpac_waf_logs" {
  bucket = aws_s3_bucket.cerpac_waf_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cerpac_waf_logs" {
  bucket = aws_s3_bucket.cerpac_waf_logs.id

  # BLOCKED requests → 90 days
  rule {
    id     = "blocked-logs-retention"
    status = "Enabled"

    filter {
      prefix = "blocked/"
    }

    expiration {
      days = 90
    }
  }

  # ALLOWED requests → 7 days
  rule {
    id     = "allowed-logs-retention"
    status = "Enabled"

    filter {
      prefix = "allowed/"
    }

    expiration {
      days = 7
    }
  }

  # BLOCKED requests → 7 days
  rule {
    id     = "errors-logs-retention"
    status = "Enabled"

    filter {
      prefix = "errors/"
    }

    expiration {
      days = 7
    }
  }

}

resource "aws_wafv2_web_acl_logging_configuration" "cerpac_waf_logging" {
  depends_on = [
    aws_kinesis_firehose_delivery_stream.cerpac_waf_logs
  ]

  resource_arn = aws_wafv2_web_acl.cerpac_waf.arn

  log_destination_configs = [
    aws_kinesis_firehose_delivery_stream.cerpac_waf_logs.arn
  ]
}

