# S3 Bucket Configuration - Usage Examples

## Overview

The module can either **create an S3 bucket** for backups or use an **existing bucket**. This gives you flexibility in how you manage backup storage.

---

## Option 1: Module Creates Bucket (Recommended)

The module automatically creates a secure S3 bucket with encryption, versioning, and lifecycle rules.

```hcl
module "mysql" {
  source = "../../databases/ec2_mysql"

  env        = "production"
  project_id = "myapp"

  # ... other config ...

  # Backups - module creates bucket
  enable_automated_backups = true
  create_backup_bucket     = true  # Default
  backup_retention_days    = 14

  # Bucket will be named: production-myapp-mysql-mysql-backups
}
```

**What gets created:**
- S3 bucket: `production-myapp-mysql-mysql-backups`
- Encryption: AES256 (server-side)
- Versioning: Enabled
- Public access: Blocked
- Lifecycle rules: Delete files after 14 days

---

## Option 2: Use Existing Bucket

If you already have an S3 bucket for backups, tell the module to use it.

```hcl
# Create bucket separately (or use existing)
resource "aws_s3_bucket" "shared_backups" {
  bucket = "company-backups"
}

resource "aws_s3_bucket_lifecycle_configuration" "shared_backups" {
  bucket = aws_s3_bucket.shared_backups.id

  rule {
    id     = "mysql-backups"
    status = "Enabled"

    filter {
      prefix = "mysql-backups/"
    }

    expiration {
      days = 30
    }
  }
}

# Use existing bucket
module "mysql" {
  source = "../../databases/ec2_mysql"

  env        = "production"
  project_id = "myapp"

  # ... other config ...

  # Backups - use existing bucket
  enable_automated_backups = true
  create_backup_bucket     = false
  backup_s3_bucket_name    = aws_s3_bucket.shared_backups.id
  backup_retention_days    = 30  # Must match lifecycle rule
}
```

---

## S3 Bucket Features

### 1. Server-Side Encryption

All backups encrypted at rest:
```hcl
rule {
  apply_server_side_encryption_by_default {
    sse_algorithm = "AES256"
  }
}
```

### 2. Versioning

Protects against accidental overwrites:
```hcl
versioning_configuration {
  status = "Enabled"
}
```

### 3. Public Access Blocking

Prevents public exposure:
```hcl
block_public_acls       = true
block_public_policy     = true
ignore_public_acls      = true
restrict_public_buckets = true
```

### 4. Lifecycle Rules

Automatic cleanup of old backups:

```hcl
# Rule 1: Delete old backups
rule {
  id     = "delete-old-backups"
  status = "Enabled"

  filter {
    prefix = "mysql-backups/"
  }

  expiration {
    days = var.backup_retention_days  # Default: 7 days
  }
}

# Rule 2: Delete old versions
rule {
  id     = "delete-old-versions"
  status = "Enabled"

  noncurrent_version_expiration {
    noncurrent_days = var.backup_retention_days
  }
}
```

---

## Cost Optimization

### Enable Tiering for Long Retention

If you need to keep backups for 90+ days, enable tiering to save costs:

Edit `s3_bucket.tf` and uncomment the tiering rule:

```hcl
rule {
  id     = "transition-to-glacier"
  status = "Enabled"

  filter {
    prefix = "mysql-backups/"
  }

  # Move to Standard-IA after 7 days (50% cheaper)
  transition {
    days          = 7
    storage_class = "STANDARD_IA"
  }

  # Move to Glacier after 30 days (80% cheaper)
  transition {
    days          = 30
    storage_class = "GLACIER"
  }

  # Delete after 90 days
  expiration {
    days = 90
  }
}
```

**Cost savings:**
- Standard S3: $0.023/GB/month
- Standard-IA: $0.0125/GB/month (46% cheaper)
- Glacier: $0.004/GB/month (83% cheaper)

---

## Security Best Practices

### ✅ What EC2 Can Do

- Upload backups to S3
- List backups in S3
- Download backups (verification)

### ❌ What EC2 Cannot Do

- Delete backups (prevented by IAM policy)
- Modify lifecycle rules
- Change bucket configuration

**Why?** Ransomware protection! If EC2 is compromised, attacker cannot delete all backups.

### Lifecycle Rules Handle Cleanup

S3 automatically deletes old backups based on lifecycle rules - no EC2 involvement needed.

---

## Backup Path Structure

Backups are organized by environment and project:

```
s3://production-myapp-mysql-mysql-backups/
└── mysql-backups/
    └── production/
        └── myapp/
            ├── mysql-backup-20260119-020001.sql.gz
            ├── mysql-backup-20260120-020001.sql.gz
            └── mysql-backup-20260121-020001.sql.gz
```

---

## Variables Summary

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_automated_backups` | Enable backups to S3 | `false` |
| `create_backup_bucket` | Module creates bucket | `true` |
| `backup_s3_bucket_name` | Existing bucket name (if create=false) | `""` |
| `backup_retention_days` | Days to keep backups | `7` |
| `backup_schedule` | Cron schedule | `"0 2 * * *"` |

---

## Complete Example

```hcl
module "mysql_production" {
  source = "../../databases/ec2_mysql"

  env        = "production"
  project_id = "myapp"

  # Instance
  ami_id     = "ami-0c55b159cbfafe1f0"
  subnet_id  = "subnet-private-1a"
  security_group_ids = ["sg-mysql"]

  # MySQL
  mysql_database = "production_db"
  mysql_user     = "app_user"

  # Backups - module creates bucket
  enable_automated_backups = true
  create_backup_bucket     = true
  backup_retention_days    = 30
  backup_schedule          = "0 3 * * *"  # 3 AM daily

  tags = {
    Environment = "production"
    Backup      = "Required"
  }
}

# Access bucket details
output "backup_bucket" {
  value = module.mysql_production.mysql.backup.s3_bucket
}
```

**Created bucket:** `production-myapp-mysql-mysql-backups`  
**Retention:** 30 days  
**Schedule:** Daily at 3 AM UTC  
**Encryption:** Yes (AES256)  
**Versioning:** Yes  

---

## Troubleshooting

### Issue: Bucket name already exists

**Error:** `BucketAlreadyExists`

**Solution:** Either:
1. Change `base_name` variable
2. Use existing bucket (set `create_backup_bucket = false`)

### Issue: Lifecycle rule not deleting old backups

**Check:**
1. Lifecycle rule is `Enabled`
2. Prefix matches backup path (`mysql-backups/`)
3. Wait 24 hours (lifecycle rules run daily)

### Issue: Too many backups accumulating

**Solutions:**
1. Reduce `backup_retention_days`
2. Check lifecycle rule configuration
3. Manually delete old backups via AWS Console

---

**The S3 bucket configuration is now complete and production-ready!** 🎉

