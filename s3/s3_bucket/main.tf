# Construct the bucket name with environment prefix
locals {
  bucket_name = "${var.environment}-${var.project_id}-${var.bucket_base_name}"
}

# S3 Bucket
resource "aws_s3_bucket" "bucket" {
  bucket = local.bucket_name

  tags = {
    Name        = local.bucket_name
    Environment = var.environment
  }
}
