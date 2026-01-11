resource "aws_kinesis_firehose_delivery_stream" "cerpac_waf_logs" {
  name = "aws-waf-logs-${var.env}-cerpac-app-alb"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn           = aws_iam_role.cerpac_waf_firehose_role.arn
    bucket_arn         = aws_s3_bucket.cerpac_waf_logs.arn

    # 🔑 REQUIRED when dynamic partitioning is enabled
    buffering_size     = 64          # MB (minimum allowed)
    buffering_interval = 60          # seconds

    compression_format = "GZIP"

    # Dynamic routing from Lambda
    prefix              = "!{partitionKeyFromLambda:log_type}/"
    error_output_prefix = "errors/"

    # Enable dynamic partitioning
    dynamic_partitioning_configuration {
      enabled = true
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = "/aws/firehose/cerpac-waf"
      log_stream_name = "S3Delivery"
    }

    # Lambda processor
    processing_configuration {
      enabled = true

      processors {
        type = "Lambda"

        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = aws_lambda_function.cerpac_waf_log_router.arn
        }
      }
    }
  }
}




resource "aws_lambda_permission" "allow_firehose" {
  statement_id  = "AllowFirehoseInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cerpac_waf_log_router.function_name
  principal     = "firehose.amazonaws.com"
  source_arn    = aws_kinesis_firehose_delivery_stream.cerpac_waf_logs.arn
}
