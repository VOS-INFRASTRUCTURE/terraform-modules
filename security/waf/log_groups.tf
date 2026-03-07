################################################################################
# CloudWatch Log Groups - WAF Module
#
# Purpose: Explicitly manage all CloudWatch log groups used by this module
#          so that retention and tags are controlled by Terraform rather than
#          left to AWS auto-creation (which creates groups with infinite retention).
#
# Log groups:
#   1. Firehose delivery stream  → /aws/firehose/<env>-<project>-waf
#   2. WAF Log Router Lambda     → /aws/lambda/<env>-<project>-waf-log-router
################################################################################

################################################################################
# Firehose Delivery Stream Log Group
#
# Used by the Kinesis Firehose cloudwatch_logging_options block inside
# waf_firehose.tf to capture S3 delivery errors and metrics.
################################################################################

resource "aws_cloudwatch_log_group" "waf_firehose" {
  count = var.enable_waf_logging ? 1 : 0

  name              = "/aws/firehose/${var.env}-${var.project_id}-waf"
  retention_in_days = 90 # 3 months — sufficient for WAF delivery audit trail

  tags = merge(
    var.tags,
    {
      Name        = "${var.env}-${var.project_id}-waf-firehose-logs"
      Environment = var.env
      Project     = var.project_id
      Purpose     = "WAF-Logging"
      ManagedBy   = "Terraform"
    }
  )
}

################################################################################
# Firehose Log Stream
#
# AWS requires the log stream to exist before the delivery stream can write to it.
# Name must match the log_stream_name set in waf_firehose.tf ("S3Delivery").
################################################################################

resource "aws_cloudwatch_log_stream" "waf_firehose_s3_delivery" {
  count = var.enable_waf_logging ? 1 : 0

  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.waf_firehose[0].name
}
#
# ################################################################################
# # WAF Log Router Lambda Log Group
# #
# # Explicitly created so retention is set to 90 days.
# # Without this, Lambda auto-creates the group with infinite retention.
# # Name must match /aws/lambda/<function_name>.
# ################################################################################
#
# resource "aws_cloudwatch_log_group" "waf_log_router_lambda" {
#   count = var.enable_waf_logging ? 1 : 0
#
#   name              = "/aws/lambda/${var.env}-${var.project_id}-waf-log-router"
#   retention_in_days = 90 # 3 months
#
#   tags = merge(
#     var.tags,
#     {
#       Name        = "${var.env}-${var.project_id}-waf-log-router-logs"
#       Environment = var.env
#       Project     = var.project_id
#       Purpose     = "WAF-LogRouter"
#       ManagedBy   = "Terraform"
#     }
#   )
# }
#
