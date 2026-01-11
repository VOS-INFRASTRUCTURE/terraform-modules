################################################################################
# CloudTrail - Core Module
#
# Purpose: Multi-region audit trail for AWS API call logging and security
#          monitoring. Delivers logs to both S3 and CloudWatch Logs.
#
# Components:
# - CloudWatch Log Group for real-time streaming (this file)
# - IAM role/policy for CloudTrail to write to CloudWatch Logs (this file)
# - Multi-region CloudTrail trail (this file)
# - S3 bucket for long-term storage (see bucket.tf)
#
# Features:
# - Multi-region coverage (captures events from all regions)
# - Global service events included (IAM, CloudFront, etc.)
# - Log file validation enabled (tamper detection)
# - Dual delivery: S3 (long-term) + CloudWatch (real-time alerts)
################################################################################

################################################################################
# Locals - Naming Consistency
################################################################################

locals {
  ct_bucket_name    = "${var.env}-${var.project_id}-cloudtrail-logs"
  ct_log_group_name = "/aws/cloudtrail/${var.env}-${var.project_id}-audit-trail"
}


################################################################################
# CloudWatch Log Group - CloudTrail Streaming
#
# Purpose: Real-time log streaming for CloudWatch-based monitoring and alerting.
#          Enables metric filters and alarms for security events.
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
# IAM Role - CloudTrail to CloudWatch Logs
#
# Purpose: Allow CloudTrail service to write logs to CloudWatch Log Group.
#
# Permissions:
# - CreateLogStream: Create new log streams
# - PutLogEvents: Write log events to streams
################################################################################

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name = "${var.env}-${var.project_id}-cloudtrail-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
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
# CloudTrail - Multi-Region Audit Trail
#
# Purpose: Capture all AWS API calls across all regions for security auditing.
#
# Features:
# - Multi-region: Captures events from ALL AWS regions
# - Global events: Includes IAM, Route53, CloudFront, etc.
# - Log validation: Enables tamper detection via cryptographic hashing
# - Dual delivery: S3 (long-term storage) + CloudWatch (real-time alerts)
#
# Event Types Captured:
# - Management events: API calls that modify resources (create, update, delete)
# - Read/Write operations: All API activity
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
