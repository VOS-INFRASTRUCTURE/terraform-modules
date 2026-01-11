# Log Group is auto created for lambda

resource "aws_iam_role" "cerpac_waf_lambda_role" {
  name = "${var.env}-cerpac-waf-lambda-role"

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
}

resource "aws_iam_role_policy_attachment" "cerpac_waf_lambda_basic" {
  role       = aws_iam_role.cerpac_waf_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "cerpac_waf_log_router" {
  function_name = "${var.env}-cerpac-waf-log-router"
  role          = aws_iam_role.cerpac_waf_lambda_role.arn
  handler       = "waf_log_router.lambda_handler"
  runtime       = "python3.11"

  timeout      = 60
  memory_size = 256

  filename         = "${path.module}/lambda/waf_log_router.zip"
  source_code_hash = filebase64sha256(
    "${path.module}/lambda/waf_log_router.zip"
  )
}

