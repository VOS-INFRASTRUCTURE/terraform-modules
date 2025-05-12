output "bucket_details" {
  description = "Details of the S3 bucket"
  value = {
    name        = aws_s3_bucket.bucket.bucket
    arn         = aws_s3_bucket.bucket.arn
    region      = var.region
    full_url    = "https://${aws_s3_bucket.bucket.bucket}.s3.${var.region}.amazonaws.com"
  }
  sensitive = true
}
