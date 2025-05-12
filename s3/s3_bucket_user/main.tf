# Construct the details
locals {
  iam_user_name = "${var.bucket_name}-user"
}

# IAM User for S3 Access
resource "aws_iam_user" "user" {
  name = local.iam_user_name

  tags = {
    Name        = local.iam_user_name
    Environment = var.environment
  }
}

# IAM Access Key for the User
resource "aws_iam_access_key" "user_key" {
  user = aws_iam_user.user.name
}

# IAM Policy for S3 Access
resource "aws_iam_policy" "policy" {
  name        = "${local.iam_user_name}_rw_policy"
  description = "Policy to allow read and write access to the bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowS3BucketAccess",
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ],
        Resource = [
          var.bucket_arn,
          "${var.bucket_arn}/*"
        ]
      }
    ]
  })
}

# Attach Policy to IAM User
resource "aws_iam_user_policy_attachment" "policy_attachment" {
  user       = aws_iam_user.user.name
  policy_arn = aws_iam_policy.policy.arn
}
