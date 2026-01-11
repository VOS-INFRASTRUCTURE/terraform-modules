################################################################################
# Kinesis Firehose IAM Role and Policy
#
# Purpose: Allow Firehose to write to S3, invoke Lambda, and write logs.
#
# Permissions:
# - S3: Write WAF logs to bucket
# - Lambda: Invoke log router function
# - CloudWatch Logs: Write delivery logs
################################################################################

resource "aws_iam_role" "waf_firehose_role" {
  count = var.enable_waf_logging ? 1 : 0

  name = "${var.env}-${var.project_id}-waf-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "firehose.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.env}-${var.project_id}-waf-firehose-role"
      Environment = var.env
      Project     = var.project_id
      Purpose     = "WAF-Firehose"
      ManagedBy   = "Terraform"
    }
  )
}

resource "aws_iam_role_policy" "waf_firehose_policy" {
  count = var.enable_waf_logging ? 1 : 0

  name = "${var.env}-${var.project_id}-waf-firehose-policy"
  role = aws_iam_role.waf_firehose_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.waf_logs[0].arn,
          "${aws_s3_bucket.waf_logs[0].arn}/*"
        ]
      },
      {
        Sid    = "LambdaInvoke"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
          "lambda:GetFunctionConfiguration"
        ]
        Resource = aws_lambda_function.waf_log_router[0].arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogStream",
          "logs:CreateLogGroup"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/firehose/*"
      }
    ]
  })
}
