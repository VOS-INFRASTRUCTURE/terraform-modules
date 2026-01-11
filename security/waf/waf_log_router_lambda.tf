################################################################################
# WAF Log Router Lambda Function
#
# Purpose: Process WAF logs from Kinesis Firehose and route them to
#          appropriate S3 prefixes based on action (blocked/allowed).
#
# Logic:
# - Blocked requests → s3://bucket/blocked/
# - Allowed requests → s3://bucket/allowed/
# - Errors → s3://bucket/errors/
#
# Note: CloudWatch Log Group is automatically created by Lambda
################################################################################

################################################################################
# IAM Role for Lambda
################################################################################

resource "aws_iam_role" "waf_lambda_role" {
  count = var.enable_waf_logging ? 1 : 0

  name = "${var.env}-${var.project_id}-waf-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.env}-${var.project_id}-waf-lambda-role"
      Environment = var.env
      Project     = var.project_id
      Purpose     = "WAF-LogRouter"
      ManagedBy   = "Terraform"
    }
  )
}

################################################################################
# IAM Policy Attachment - Basic Lambda Execution
################################################################################

resource "aws_iam_role_policy_attachment" "waf_lambda_basic" {
  count = var.enable_waf_logging ? 1 : 0

  role       = aws_iam_role.waf_lambda_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

################################################################################
# Lambda Function - WAF Log Router
################################################################################

resource "aws_lambda_function" "waf_log_router" {
  count = var.enable_waf_logging ? 1 : 0

  function_name = "${var.env}-${var.project_id}-waf-log-router"
  role          = aws_iam_role.waf_lambda_role[0].arn
  handler       = "waf_log_router.lambda_handler"
  runtime       = "python3.11"

  timeout     = 60
  memory_size = 256

  filename         = "${path.module}/lambda/waf_log_router.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/waf_log_router.zip")

  tags = merge(
    var.tags,
    {
      Name        = "${var.env}-${var.project_id}-waf-log-router"
      Environment = var.env
      Project     = var.project_id
      Purpose     = "WAF-LogRouter"
      ManagedBy   = "Terraform"
    }
  )
}

