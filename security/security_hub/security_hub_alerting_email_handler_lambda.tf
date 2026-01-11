################################################################################
# EMAIL ALERT HANDLER LAMBDA – Beautiful HTML Email Formatter
# Purpose: Format Security Hub/GuardDuty findings into beautiful HTML emails
#          and send via Amazon SES (only HIGH/CRITICAL severity)
# Related: lambda/security_alert_email_handler.py
################################################################################

locals {
  email_lambda_name = "${var.env}-${var.project_id}-security-email-handler"
}

################################################################################
# IAM ROLE FOR EMAIL HANDLER LAMBDA
################################################################################

resource "aws_iam_role" "security_email_lambda_role" {
  count = var.enable_security_alerting && var.enable_email_handler ? 1 : 0

  name = "${var.env}-${var.project_id}-security-email-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "SecurityEmailHandler"
  }
}

################################################################################
# IAM POLICY – BASIC LAMBDA EXECUTION (CLOUDWATCH LOGS)
################################################################################

resource "aws_iam_role_policy_attachment" "security_email_lambda_basic_logs" {
  count = var.enable_security_alerting && var.enable_email_handler ? 1 : 0

  role       = aws_iam_role.security_email_lambda_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

################################################################################
# IAM POLICY – SES SEND EMAIL PERMISSIONS
################################################################################

resource "aws_iam_role_policy" "security_email_lambda_ses" {
  count = var.enable_security_alerting && var.enable_email_handler ? 1 : 0

  name = "${var.env}-${var.project_id}-security-email-lambda-ses-policy"
  role = aws_iam_role.security_email_lambda_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSESSendEmail"
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ses:FromAddress" = var.ses_from_email
          }
        }
      }
    ]
  })
}

################################################################################
# LAMBDA FUNCTION – SECURITY EMAIL HANDLER
################################################################################

resource "aws_lambda_function" "security_email_handler" {
  count = var.enable_security_alerting && var.enable_email_handler ? 1 : 0

  function_name = local.email_lambda_name
  role          = aws_iam_role.security_email_lambda_role[0].arn
  handler       = "security_alert_email_handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30
  memory_size   = 256

  filename         = "${path.module}/lambda/security_alert_email_handler.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/security_alert_email_handler.zip")

  environment {
    variables = {
      FROM_EMAIL = var.ses_from_email
      TO_EMAILS  = join(",", var.ses_to_emails)
      LOG_LEVEL  = var.lambda_log_level
    }
  }

  tags = {
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "SecurityEmailFormatter"
  }
}

################################################################################
# SNS → LAMBDA SUBSCRIPTION (EMAIL HANDLER)
################################################################################

resource "aws_sns_topic_subscription" "security_alerts_email_lambda" {
  count = var.enable_security_alerting && var.enable_email_handler ? 1 : 0

  depends_on = [aws_lambda_function.security_email_handler]

  topic_arn = aws_sns_topic.security_alerts[0].arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.security_email_handler[0].arn
}

################################################################################
# LAMBDA PERMISSION – ALLOW SNS TO INVOKE
################################################################################

resource "aws_lambda_permission" "allow_sns_email_handler" {
  count = var.enable_security_alerting && var.enable_email_handler ? 1 : 0

  statement_id  = "AllowSNSTriggerEmailHandler"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_email_handler[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.security_alerts[0].arn
}

