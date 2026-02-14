################################################################################
# WAF Logging Configuration
#
# Purpose: Configure WAF to send logs to Kinesis Firehose for delivery to S3.
#
# Architecture:
# WAF → Kinesis Firehose → Lambda (routing) → S3 (partitioned by log type)
#
# Note: S3 bucket configuration is in bucket.tf
################################################################################

resource "aws_wafv2_web_acl_logging_configuration" "waf_logging" {
  count = var.enable_waf && var.enable_waf_logging ? 1 : 0

  depends_on = [
    aws_kinesis_firehose_delivery_stream.waf_logs
  ]

  resource_arn = aws_wafv2_web_acl.waf[0].arn

  log_destination_configs = [
    aws_kinesis_firehose_delivery_stream.waf_logs[0].arn
  ]
}

