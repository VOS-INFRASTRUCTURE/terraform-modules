################################################################################
# ALERT NORMALIZER LAMBDA – Slack Forwarder
# Purpose: Normalize Security Hub/GuardDuty findings and forward to Slack.
# Related: lambda/security_alert_normalizer.py, env LOG_LEVEL, SLACK_WEBHOOK_URL
################################################################################

################################################################################
# SECURITY ALERT NORMALIZER – SLACK FORWARDER LAMBDA
################################################################################

resource "aws_iam_role" "security_alert_lambda_role" {
  name = "${var.env}-${var.project_id}-security-alert-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "security_alert_lambda_basic_logs" {
  role       = aws_iam_role.security_alert_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "security_alert_normalizer" {
  function_name = "${var.env}-${var.project_id}-security-alert-normalizer"
  role          = aws_iam_role.security_alert_lambda_role.arn
  handler       = "security_alert_normalizer.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30
  memory_size   = 256

  filename         = "${path.module}/lambda/security_alert_normalizer.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/security_alert_normalizer.zip")

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.security_slack_webhook_url
      PROJECT_NAME      = var.project_id
      LOG_LEVEL         = "INFO"
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
  depends_on = [aws_lambda_function.security_alert_normalizer]

  topic_arn = aws_sns_topic.security_alerts[0].arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.security_alert_normalizer.arn
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowSNSTrigger"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_alert_normalizer.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.security_alerts[0].arn
}
