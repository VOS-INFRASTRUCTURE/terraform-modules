resource "aws_kms_key" "firehose" {
  description             = "KMS key for WAF Firehose encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name        = "${var.env}-${var.project_id}-waf-firehose-kms"
    Environment = var.env
    Project     = var.project_id
    Purpose     = "Waf-Firehose-Encryption"
  }
}


data "aws_iam_policy_document" "firehose_kms" {
  statement {
    sid    = "AllowRootAccount"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowFirehoseUse"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }

    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:ReEncrypt*",
      "kms:DescribeKey"
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_kinesis_firehose_delivery_stream.waf_logs[0].arn]
    }
  }

  # 3️⃣ Optional: Allow Lambda processor to read/write encrypted objects
  statement {
    sid    = "AllowLambdaProcessing"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.waf_lambda_role[0].arn]
    }

    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt"
    ]

    resources = ["*"]
  }
}

resource "aws_kms_key_policy" "firehose" {
  key_id = aws_kms_key.firehose.id
  policy = data.aws_iam_policy_document.firehose_kms.json
}