# ============================================================================
# Outputs – CloudTrail Module
# Purpose: Expose a single grouped object for bucket, log group, and trail.
# ============================================================================

output "cloudtrail" {
  description = "Grouped CloudTrail identifiers"
  value = {
    bucket_name    = aws_s3_bucket.cloudtrail_logs.bucket
    bucket_arn     = aws_s3_bucket.cloudtrail_logs.arn
    log_group_name = aws_cloudwatch_log_group.this.name
    log_group_arn  = aws_cloudwatch_log_group.this.arn
    trail_arn      = aws_cloudtrail.trail.arn
  }
}
