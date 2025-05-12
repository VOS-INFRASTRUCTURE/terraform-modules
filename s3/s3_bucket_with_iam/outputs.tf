output "bucket_details" {
  description = "Details of the S3 bucket"
  value = {
    name        = aws_s3_bucket.bucket.bucket
    arn         = aws_s3_bucket.bucket.arn
    region      = var.region
    full_url    = "https://${aws_s3_bucket.bucket.bucket}.s3.${var.region}.amazonaws.com"
    iam_user    = {
      user_name   = aws_iam_user.user.name
      access_key  = aws_iam_access_key.user_key.id
      secret_key  = aws_iam_access_key.user_key.secret
    }
    sensitive = true
  }
}
