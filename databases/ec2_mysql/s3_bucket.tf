################################################################################
# S3 Bucket for MySQL Backups
#
# Purpose: Store automated MySQL backups with lifecycle management
#
# Security Features:
# - Server-side encryption (AES256)
# - Versioning enabled (protect against accidental overwrites)
# - Public access blocked
# - Lifecycle rules for automatic cleanup (EC2 cannot delete backups)
#
# Note: This bucket is OPTIONAL. Only created if enable_automated_backups = true
#       and backup_s3_bucket_name is NOT provided (module creates bucket).
################################################################################

################################################################################
# S3 Bucket
################################################################################

resource "aws_s3_bucket" "mysql_backups" {
  count = var.enable_automated_backups && var.create_backup_bucket ? 1 : 0

  bucket        = "${var.env}-${var.project_id}-${var.base_name}-mysql-backups"
  force_destroy = false  # Prevent accidental deletion with backups inside

  tags = merge(
    var.tags,
    {
      Name        = "${var.env}-${var.project_id}-${var.base_name}-mysql-backups"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "MySQL-Backups"
      Retention   = "${var.backup_retention_days} days"
    }
  )
}

################################################################################
# Block Public Access
################################################################################

resource "aws_s3_bucket_public_access_block" "mysql_backups" {
  count  = var.enable_automated_backups && var.create_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.mysql_backups[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

################################################################################
# Server-Side Encryption
################################################################################

resource "aws_s3_bucket_server_side_encryption_configuration" "mysql_backups" {
  count  = var.enable_automated_backups && var.create_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.mysql_backups[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

################################################################################
# Versioning
################################################################################

resource "aws_s3_bucket_versioning" "mysql_backups" {
  count  = var.enable_automated_backups && var.create_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.mysql_backups[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

################################################################################
# Lifecycle Rules - Automatic Backup Retention Management
#
# Security Note: EC2 instance does NOT have s3:DeleteObject permission.
# S3 lifecycle rules handle automatic cleanup of old backups.
# This prevents compromised EC2 from deleting all backups (ransomware protection).
################################################################################

resource "aws_s3_bucket_lifecycle_configuration" "mysql_backups" {
  count  = var.enable_automated_backups && var.create_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.mysql_backups[0].id

  # Rule 1: Delete old backup files after retention period
  rule {
    id     = "delete-old-backups"
    status = "Enabled"

    filter {
      prefix = "mysql-backups/"
    }

    expiration {
      days = var.backup_retention_days
    }
  }

  # Rule 2: Delete old versions after retention period (if versioning enabled)
  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    filter {
      prefix = "mysql-backups/"
    }

    noncurrent_version_expiration {
      noncurrent_days = var.backup_retention_days
    }
  }

  # Rule 3: (Optional) Transition to cheaper storage classes
  # Uncomment to save costs on older backups
  # rule {
  #   id     = "transition-to-glacier"
  #   status = "Enabled"
  #
  #   filter {
  #     prefix = "mysql-backups/"
  #   }
  #
  #   # Move to Standard-IA after 7 days
  #   transition {
  #     days          = 7
  #     storage_class = "STANDARD_IA"
  #   }
  #
  #   # Move to Glacier after 30 days
  #   transition {
  #     days          = 30
  #     storage_class = "GLACIER"
  #   }
  #
  #   expiration {
  #     days = var.backup_retention_days
  #   }
  # }
}

################################################################################
# Bucket Policy (Optional - for cross-account access or additional restrictions)
################################################################################

# Uncomment if you need additional bucket policies
# resource "aws_s3_bucket_policy" "mysql_backups" {
#   count  = var.enable_automated_backups && var.create_backup_bucket ? 1 : 0
#   bucket = aws_s3_bucket.mysql_backups[0].id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Sid    = "DenyInsecureTransport"
#         Effect = "Deny"
#         Principal = "*"
#         Action = "s3:*"
#         Resource = [
#           aws_s3_bucket.mysql_backups[0].arn,
#           "${aws_s3_bucket.mysql_backups[0].arn}/*"
#         ]
#         Condition = {
#           Bool = {
#             "aws:SecureTransport" = "false"
#           }
#         }
#       }
#     ]
#   })
# }


