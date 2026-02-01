# EC2 MySQL Module - Security Architecture

## 🔒 Security Questions Answered

### Q: Why do we have `aws_secretsmanager_secret` resources? Doesn't EC2 create them?

**A: No! Terraform creates the secrets, EC2 only reads them.**

### Architecture Flow

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Terraform (Your Laptop/CI)                              │
│    - Creates Secrets Manager secrets                        │
│    - Generates random passwords (if not provided)           │
│    - Stores passwords in Secrets Manager (encrypted)        │
│    - Creates IAM role with READ-ONLY permissions            │
│    - Creates EC2 instance                                   │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. EC2 Instance (MySQL Server)                             │
│    - READS passwords from Secrets Manager (via IAM role)   │
│    - Uses passwords to configure MySQL container           │
│    - CANNOT create, update, or delete secrets              │
│    - CANNOT delete S3 backups                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔐 IAM Permissions Breakdown

### What EC2 Instance CAN Do

| Service | Permission | Why? |
|---------|-----------|------|
| **Secrets Manager** | `GetSecretValue` | Read password values |
| **Secrets Manager** | `DescribeSecret` | Read secret metadata |
| **S3** | `PutObject` | Upload backups to S3 |
| **S3** | `GetObject` | Download backups (verification) |
| **S3** | `ListBucket` | List existing backups |
| **CloudWatch** | `PutMetricData` | Send custom metrics |
| **CloudWatch Logs** | `CreateLogGroup` | Create log groups |
| **CloudWatch Logs** | `CreateLogStream` | Create log streams |
| **CloudWatch Logs** | `PutLogEvents` | Send log events |
| **SSM** | Session Manager | SSH-less access |

### What EC2 Instance CANNOT Do (Security)

| Service | Blocked Permission | Why Blocked? |
|---------|-------------------|--------------|
| **Secrets Manager** | `CreateSecret` | Only Terraform creates secrets |
| **Secrets Manager** | `UpdateSecret` | Only Terraform updates secrets |
| **Secrets Manager** | `DeleteSecret` | Only Terraform deletes secrets |
| **Secrets Manager** | `PutSecretValue` | Only Terraform changes passwords |
| **S3** | `DeleteObject` | ⚠️ **Security Risk!** Prevents backup deletion |
| **IAM** | Any action | EC2 cannot modify its own permissions |
| **EC2** | Launch/Terminate | EC2 cannot create more instances |

---

## 🎯 Security Benefits of This Design

### 1. Secrets Manager - Read-Only

**Why this is secure:**
```
❌ BAD (if EC2 had write access):
   Compromised EC2 → Modify passwords → Lock out admins
   Compromised EC2 → Delete secrets → Break all apps
   Compromised EC2 → Read other secrets → Steal credentials

✅ GOOD (read-only access):
   Compromised EC2 → Can only read its own passwords
   Compromised EC2 → Cannot modify or delete secrets
   Compromised EC2 → Cannot access other project secrets
```

**How it works:**
- Terraform creates secrets during `terraform apply`
- EC2 instance profile has IAM policy scoped to ONLY these 2 secrets:
  - `${env}/${project_id}/${base_name}/mysql-root-password`
  - `${env}/${project_id}/${base_name}/mysql-user-password`
- EC2 fetches passwords at startup via AWS CLI
- EC2 cannot modify the secrets

### 2. S3 Backups - Write-Only (No Delete)

**Why this is secure:**
```
❌ BAD (if EC2 had delete access):
   Compromised EC2 → Delete all backups → No recovery possible
   Ransomware attack → Encrypt MySQL + delete backups → Total loss
   Malicious script → Delete backups older than 1 day → No retention

✅ GOOD (write-only, no delete):
   Compromised EC2 → Can only upload backups
   Ransomware attack → Backups remain safe in S3
   Malicious script → Cannot delete existing backups
```

**Backup retention management:**
Instead of EC2 deleting old backups, use one of these secure methods:

#### Option A: S3 Lifecycle Rules (Recommended)
```hcl
resource "aws_s3_bucket_lifecycle_configuration" "mysql_backups" {
  bucket = aws_s3_bucket.mysql_backups.id

  rule {
    id     = "delete-old-backups"
    status = "Enabled"

    expiration {
      days = var.backup_retention_days  # e.g., 7 or 30 days
    }

    filter {
      prefix = "mysql-backups/"
    }
  }
}
```

#### Option B: S3 Versioning + Noncurrent Expiration
```hcl
resource "aws_s3_bucket_versioning" "mysql_backups" {
  bucket = aws_s3_bucket.mysql_backups.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "mysql_backups" {
  bucket = aws_s3_bucket.mysql_backups.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.backup_retention_days
    }
  }
}
```

#### Option C: Lambda Function (Admin-only)
```hcl
# Lambda with admin permissions to delete old backups
# Triggered by EventBridge daily schedule
# Has s3:DeleteObject permission (EC2 does not)
```

---

## 📋 Who Can Do What

| Action | Terraform | EC2 Instance | Admins (IAM Users) |
|--------|-----------|--------------|-------------------|
| **Create secrets** | ✅ Yes | ❌ No | ✅ Yes (if IAM allows) |
| **Read secrets** | ✅ Yes | ✅ Yes (scoped) | ✅ Yes (if IAM allows) |
| **Update secrets** | ✅ Yes | ❌ No | ✅ Yes (if IAM allows) |
| **Delete secrets** | ✅ Yes | ❌ No | ✅ Yes (if IAM allows) |
| **Upload backups** | ❌ No | ✅ Yes | ✅ Yes (if IAM allows) |
| **Delete backups** | ✅ Yes | ❌ No | ✅ Yes (if IAM allows) |
| **Modify IAM** | ✅ Yes | ❌ No | ✅ Yes (if IAM allows) |

---

## 🔍 Common Misconceptions Clarified

### Misconception 1: "EC2 creates the Secrets Manager secrets"

**Reality:** 
- Terraform creates the secrets during deployment
- EC2 only reads them during startup
- User data script fetches passwords using AWS CLI

```bash
# This is what EC2 does (read-only):
MYSQL_ROOT_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id production/myapp/mysql/mysql-root-password \
  --query SecretString \
  --output text)

# EC2 CANNOT do this (no permission):
aws secretsmanager create-secret ...  # ❌ AccessDenied
aws secretsmanager update-secret ...  # ❌ AccessDenied
aws secretsmanager delete-secret ...  # ❌ AccessDenied
```

### Misconception 2: "EC2 needs delete permission to clean up old backups"

**Reality:**
- S3 lifecycle rules handle cleanup automatically
- EC2 deleting backups = security risk (ransomware can delete all backups)
- Separation of duties: EC2 creates backups, S3/Lambda deletes old ones

---

## 🛡️ Defense in Depth

This design implements multiple security layers:

### Layer 1: Least Privilege IAM
- EC2 can only read specific secrets
- EC2 can only write to specific S3 bucket
- No permissions to modify AWS infrastructure

### Layer 2: Secrets Manager Encryption
- All passwords encrypted at rest (AWS KMS)
- Passwords retrieved over TLS
- Access logged in CloudTrail

### Layer 3: S3 Protection
- EC2 cannot delete backups
- Versioning protects against accidental overwrites
- MFA delete option available

### Layer 4: CloudTrail Auditing
- All secret access logged
- All S3 operations logged
- Alerts on suspicious activity

### Layer 5: Network Isolation
- EC2 in private subnet
- Security groups restrict MySQL port
- SSM Session Manager (no SSH keys)

---

## ✅ Security Checklist

Before deploying:

- [ ] Secrets created by Terraform (not EC2) ✅
- [ ] EC2 has read-only access to Secrets Manager ✅
- [ ] EC2 cannot delete S3 backups ✅
- [ ] S3 lifecycle rules configured for retention
- [ ] CloudTrail enabled for audit logging
- [ ] EC2 in private subnet
- [ ] Security groups restrict MySQL access
- [ ] EBS volumes encrypted
- [ ] SSM Session Manager enabled (no SSH keys)
- [ ] CloudWatch monitoring enabled

---

## 📖 Summary

**Your concerns were 100% correct!**

✅ **Secrets Manager**: EC2 only reads secrets (Terraform creates them)  
✅ **S3 Delete**: Removed `s3:DeleteObject` permission from EC2  
✅ **Backup Retention**: Managed by S3 lifecycle rules, not EC2  

The module now follows the **principle of least privilege** - EC2 has only the minimum permissions needed to function, and nothing more.

---

## 🔗 Related Files

- `ec2_iam_role.tf` - IAM role and policies (read-only Secrets Manager, write-only S3)
- `main.tf` - Secrets Manager resources (created by Terraform)
- `user_data.tf` - Startup script (reads secrets, uploads backups)
- `SECURITY_IMPROVEMENTS.md` - Detailed security documentation

**All security concerns addressed!** 🔒

