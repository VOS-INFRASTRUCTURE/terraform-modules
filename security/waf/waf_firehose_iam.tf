################################################################################
# Kinesis Firehose IAM Role and Policy
#
# Purpose: Allow Firehose to write to S3, invoke Lambda, and write logs.
#
# Permissions:
# - S3: Write WAF logs to bucket (local OR cross-account central bucket)
# - KMS: Encrypt/decrypt data for Firehose stream encryption
# - Lambda: Invoke log router function
# - CloudWatch Logs: Write delivery logs
#
# Cross-account notes (when central_s3_bucket_name is set):
# - The Firehose role in THIS account needs s3:PutObject etc. on the
#   central bucket ARN  ← already handled via local.effective_s3_bucket_arn
# - The central bucket's RESOURCE POLICY must also allow this role
#   ← use the waf_central_bucket_policy output to get the exact JSON
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
      # Restrict assumption to this account only — prevents confused deputy
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
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
        # S3 write access — resolves to either the local bucket or the
        # central cross-account bucket via local.effective_s3_bucket_arn.
        # For cross-account delivery the central bucket's resource policy
        # must ALSO allow this role (use waf_central_bucket_policy output).
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads"
        ]
        Resource = [
          local.effective_s3_bucket_arn,
          "${local.effective_s3_bucket_arn}/*"
        ]
      },
      {
        # KMS permissions for Firehose stream SSE (CUSTOMER_MANAGED_CMK).
        # Required so Firehose can encrypt/decrypt the stream data before
        # writing to S3.
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:ReEncrypt*",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.firehose.arn
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

################################################################################
# Lambda S3 Write Policy
#
# Purpose: Allow the WAF Log Router Lambda to write directly to S3.
#
# Why Lambda needs S3 access:
# In this architecture Firehose uses Lambda as a *record transformer* (it
# adds partition keys). Firehose—not Lambda—writes the final records to S3.
# However, Lambda DOES need s3:PutObject when it writes error/debug output
# directly, and some routing patterns write directly from Lambda.
#
# For cross-account delivery (central_s3_bucket_name set) the Lambda role
# also needs permission on the central bucket so that any direct writes
# from Lambda land correctly.
################################################################################

resource "aws_iam_role_policy" "waf_lambda_s3_policy" {
  count = var.enable_waf_logging ? 1 : 0

  name = "${var.env}-${var.project_id}-waf-lambda-s3-policy"
  role = aws_iam_role.waf_lambda_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Write access to whichever bucket is active (local or central).
        # For cross-account (central bucket) the bucket resource policy must
        # also allow this Lambda role ARN — see waf_central_bucket_policy output.
        Sid    = "S3WriteAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:AbortMultipartUpload"
        ]
        Resource = "${local.effective_s3_bucket_arn}/*"
      }
    ]
  })
}

