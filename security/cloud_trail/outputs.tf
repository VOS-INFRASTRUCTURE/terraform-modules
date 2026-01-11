################################################################################
# CloudTrail Module Outputs
#
# All outputs are consolidated into a single 'cloudtrail' object for easier
# consumption and cleaner code organization.
#
# Usage:
#   module.cloudtrail.cloudtrail.bucket.name
#   module.cloudtrail.cloudtrail.trail.is_multi_region
#   module.cloudtrail.cloudtrail.log_group.retention_days
################################################################################

output "cloudtrail" {
  description = "CloudTrail resources and configuration details"
  value = {
    # ──────────────────────────────────────────────────────────────────────
    # S3 Bucket - Long-term audit log storage
    # ──────────────────────────────────────────────────────────────────────
    bucket = {
      name       = aws_s3_bucket.cloudtrail_logs.bucket      # S3 bucket name
      arn        = aws_s3_bucket.cloudtrail_logs.arn         # S3 bucket ARN
      id         = aws_s3_bucket.cloudtrail_logs.id          # S3 bucket ID
      versioning = "Enabled"                                  # Versioning status
      encryption = "AES256"                                   # Encryption type
    }

    # ──────────────────────────────────────────────────────────────────────
    # CloudWatch Log Group - Real-time log streaming
    # ──────────────────────────────────────────────────────────────────────
    log_group = {
      name           = aws_cloudwatch_log_group.this.name    # Log group name
      arn            = aws_cloudwatch_log_group.this.arn     # Log group ARN
      retention_days = var.retention_days                    # Retention period
    }

    # ──────────────────────────────────────────────────────────────────────
    # CloudTrail - Multi-region audit trail
    # ──────────────────────────────────────────────────────────────────────
    trail = {
      name              = aws_cloudtrail.trail.name          # Trail name
      arn               = aws_cloudtrail.trail.arn           # Trail ARN
      id                = aws_cloudtrail.trail.id            # Trail ID
      is_multi_region   = true                               # Multi-region enabled
      log_validation    = true                               # Log file validation enabled
      global_events     = true                               # Global service events included
      home_region       = aws_cloudtrail.trail.home_region   # Home region
    }

    # ──────────────────────────────────────────────────────────────────────
    # IAM Role - CloudTrail to CloudWatch Logs
    # ──────────────────────────────────────────────────────────────────────
    iam_role = {
      name = aws_iam_role.cloudtrail_cloudwatch.name        # IAM role name
      arn  = aws_iam_role.cloudtrail_cloudwatch.arn         # IAM role ARN
    }

    # ──────────────────────────────────────────────────────────────────────
    # Configuration Summary - Quick reference for module status
    # ──────────────────────────────────────────────────────────────────────
    summary = {
      module_enabled     = true                              # Module is active
      dual_delivery      = true                              # Both S3 and CloudWatch
      retention_days     = var.retention_days                # Log retention period
      force_destroy      = var.force_destroy                 # Bucket force destroy setting
    }
  }
}
