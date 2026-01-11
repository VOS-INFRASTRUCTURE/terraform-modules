################################################################################
# CERPAC – CloudTrail Core Module
# - S3 bucket (logs), encryption, lifecycle, versioning
# - CloudWatch Log Group for streaming
# - IAM role/policy for CloudTrail to write to CloudWatch Logs
# - Multi-region CloudTrail trail
################################################################################

################################################################################
# SHARED LOCALS – NAMING CONSISTENCY
################################################################################

locals {
  ct_bucket_name    = "${var.env}-${var.project_id}-cloudtrail-logs"
  ct_log_group_name = "/aws/cloudtrail/${var.env}-${var.project_id}-audit-trail"
}

################################################################################
# S3 BUCKET – CLOUDTRAIL LOG STORAGE
################################################################################

resource "aws_s3_bucket" "cloudtrail_logs" {
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

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

################################################################################
# S3 LIFECYCLE – RETENTION
################################################################################

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

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

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

################################################################################
# S3 BUCKET POLICY – ALLOW CLOUDTRAIL WRITE
################################################################################

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/*"
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
# CLOUDWATCH LOG GROUP – CLOUDTRAIL STREAMING
################################################################################

resource "aws_cloudwatch_log_group" "this" {
  name              = local.ct_log_group_name
  retention_in_days = var.retention_days

  tags = {
    Name        = "${var.env}-${var.project_id}-cloudtrail"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
  }
}

################################################################################
# IAM ROLE – CLOUDTRAIL → CLOUDWATCH LOGS
################################################################################

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name = "${var.env}-${var.project_id}-cloudtrail-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  role = aws_iam_role.cloudtrail_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.this.arn}:*"
    }]
  })
}

################################################################################
# CLOUDTRAIL – MULTI-REGION AUDIT TRAIL
################################################################################

resource "aws_cloudtrail" "trail" {
  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_cloudwatch_log_group.this,
    aws_iam_role.cloudtrail_cloudwatch,
    aws_iam_role_policy.cloudtrail_cloudwatch
  ]

  name                          = "${var.env}-${var.project_id}-audit-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true
  enable_log_file_validation    = true

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.this.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = {
    Name        = "${var.env}-${var.project_id}-audit-trail"
    Environment = var.env
    Project     = var.project_id
    Purpose     = "SecurityAudit"
    Compliance  = "Required"
    ManagedBy   = "Terraform"
  }
}
