################################################################################
# ALERT NORMALIZER LAMBDA – Slack Forwarder
# Purpose: Normalize Security Hub/GuardDuty findings and forward to Slack.
# Related: lambda/security_alert_slack_handler.py, env LOG_LEVEL, SLACK_WEBHOOK_URL
# Only created if enable_slack_alerts = true
################################################################################

################################################################################
# IAM ROLE FOR SLACK ALERT LAMBDA
################################################################################

resource "aws_iam_role" "security_alert_lambda_role" {
  count = var.enable_slack_alerts ? 1 : 0

  name = "${var.env}-${var.project_id}-security-alert-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "SecuritySlackAlerts"
  }
}

resource "aws_iam_role_policy_attachment" "security_alert_lambda_basic_logs" {
  count = var.enable_slack_alerts ? 1 : 0

  role       = aws_iam_role.security_alert_lambda_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

################################################################################
# CLOUDWATCH LOG GROUP – SLACK LAMBDA
# Purpose: Explicitly create log group with retention to prevent infinite growth
# Note: Must match Lambda function name exactly: /aws/lambda/{function-name}
################################################################################

resource "aws_cloudwatch_log_group" "security_alert_slack_handler" {
  count = var.enable_slack_alerts ? 1 : 0

  name              = "/aws/lambda/${var.env}-${var.project_id}-security-alert-slack-handler"
  retention_in_days = 90  # 3 months retention for security logs

  tags = {
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "SecuritySlackAlerts"
  }
}

# Additional policy to ensure Lambda can write to the specific log group we created
resource "aws_iam_role_policy" "security_alert_lambda_logs" {
  count = var.enable_slack_alerts ? 1 : 0

  name = "${var.env}-${var.project_id}-security-alert-lambda-logs-policy"
  role = aws_iam_role.security_alert_lambda_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.security_alert_slack_handler[0].arn}:*"
      }
    ]
  })
}

################################################################################
# LAMBDA FUNCTION – SECURITY ALERT NORMALIZER (SLACK)
################################################################################

resource "aws_lambda_function" "security_alert_slack_handler" {
  count = var.enable_slack_alerts ? 1 : 0

  # Ensure log group and IAM permissions exist before Lambda is created
  depends_on = [
    aws_cloudwatch_log_group.security_alert_slack_handler,
    aws_iam_role_policy.security_alert_lambda_logs
  ]

  function_name = "${var.env}-${var.project_id}-security-alert-slack-handler"
  // ...existing code...
  role          = aws_iam_role.security_alert_lambda_role[0].arn
  handler       = "security_alert_slack_handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30
  memory_size   = 256

  filename         = "${path.module}/lambda/security_alert_slack_handler.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/security_alert_slack_handler.zip")

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.security_slack_webhook_url
      PROJECT_NAME      = var.project_id
      ENVIRONMENT       = var.env
      LOG_LEVEL         = var.lambda_log_level
    }
  }

  tags = {
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "SecurityAlertNormalization"
  }
}

################################################################################
# SNS → LAMBDA SUBSCRIPTION
################################################################################

resource "aws_sns_topic_subscription" "security_alerts_lambda" {
  count = var.enable_slack_alerts ? 1 : 0

  depends_on = [aws_lambda_function.security_alert_slack_handler]

  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.security_alert_slack_handler[0].arn
}

resource "aws_lambda_permission" "allow_sns" {
  count = var.enable_slack_alerts ? 1 : 0

  statement_id  = "AllowSNSTrigger"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_alert_slack_handler[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.security_alerts.arn
}
