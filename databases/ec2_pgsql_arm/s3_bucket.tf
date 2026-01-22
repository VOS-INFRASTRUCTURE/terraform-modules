################################################################################
# S3 Bucket for PostgreSQL Backups
################################################################################

resource "aws_s3_bucket" "backup" {
  count         = var.enable_automated_backups && var.create_backup_bucket ? 1 : 0
  bucket        = local.backup_bucket_name
  force_destroy = false

  tags = merge(
    var.tags,
    {
      Name        = local.backup_bucket_name
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "PostgreSQL-Backups"
    }
  )
}

resource "aws_s3_bucket_public_access_block" "backup" {
  count  = var.enable_automated_backups && var.create_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.backup[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  count  = var.enable_automated_backups && var.create_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.backup[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "backup" {
  count  = var.enable_automated_backups && var.create_backup_bucket && var.enable_backup_versioning ? 1 : 0
  bucket = aws_s3_bucket.backup[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  count  = var.enable_automated_backups && var.create_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.backup[0].id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.backup_retention_days
    }
  }
}

