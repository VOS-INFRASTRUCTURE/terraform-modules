################################################################################
# Kinesis Firehose Delivery Stream for WAF Logs
#
# Purpose: Deliver WAF logs to S3 with intelligent routing via Lambda.
#
# Features:
# - Dynamic partitioning (blocked/, allowed/, errors/)
# - GZIP compression for cost savings
# - Lambda processor for log routing
# - CloudWatch logging for monitoring
################################################################################

resource "aws_kinesis_firehose_delivery_stream" "waf_logs" {
  count = var.enable_waf_logging ? 1 : 0

  name        = "aws-waf-logs-${var.env}-${var.project_id}-${local.frontend_alb_key_name}"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.waf_firehose_role[0].arn
    bucket_arn = aws_s3_bucket.waf_logs[0].arn

    # Required when dynamic partitioning is enabled
    buffering_size     = var.firehose_buffering_size      # MB (minimum: 64)
    buffering_interval = var.firehose_buffering_interval  # seconds

    compression_format = var.enable_firehose_compression ? "GZIP" : "UNCOMPRESSED"

    # Dynamic routing from Lambda
    prefix              = "!{partitionKeyFromLambda:log_type}/"
    error_output_prefix = "errors/"

    # Enable dynamic partitioning
    dynamic_partitioning_configuration {
      enabled = true
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = "/aws/firehose/${var.env}-${var.project_id}-waf"
      log_stream_name = "S3Delivery"
    }

    # Lambda processor for log routing
    processing_configuration {
      enabled = true

      processors {
        type = "Lambda"

        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = aws_lambda_function.waf_log_router[0].arn
        }
      }
    }


  }

  server_side_encryption {
    enabled  = true
    key_type = "CUSTOMER_MANAGED_CMK"
    key_arn  = aws_kms_key.firehose.arn
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.env}-${var.project_id}-waf-firehose"
      Environment = var.env
      Project     = var.project_id
      Purpose     = "WAF-Logging"
      ManagedBy   = "Terraform"
    }
  )
}

################################################################################
# Lambda Permission - Allow Firehose to Invoke
################################################################################

resource "aws_lambda_permission" "allow_firehose" {
  count = var.enable_waf_logging ? 1 : 0

  statement_id  = "AllowFirehoseInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.waf_log_router[0].function_name
  principal     = "firehose.amazonaws.com"
  source_arn    = aws_kinesis_firehose_delivery_stream.waf_logs[0].arn
}
