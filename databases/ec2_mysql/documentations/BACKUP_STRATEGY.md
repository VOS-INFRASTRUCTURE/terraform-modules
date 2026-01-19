################################################################################
# EC2 MySQL Backup Strategy - Summary
################################################################################

This module now provides TWO layers of backup protection:

## 1️⃣ MySQL Database Backups (S3)
   
   **Technology**: mysqldump + gzip → S3
   **What's backed up**: MySQL databases only (logical backup)
   **Frequency**: Hourly (default: 0 * * * *)
   **Retention**: 7 days (configurable)
   **Cost**: ~$0.023/GB/month (S3 Standard)
   
   **Use cases**:
   - Database corruption
   - Accidental data deletion
   - Table/row recovery
   - Cross-region disaster recovery
   - Point-in-time recovery (hourly granularity)
   
   **Restore time**: 5-15 minutes (fast)
   **Restore scope**: Database level

## 2️⃣ EBS Volume Snapshots (AWS DLM)

   **Technology**: AWS Data Lifecycle Manager (block-level snapshots)
   **What's backed up**: Entire EBS volume (OS + Docker + MySQL + configs)
   **Frequency**: Daily at 3 AM UTC (default)
   **Retention**: 7 snapshots (configurable)
   **Cost**: ~$0.05/GB/month (incremental snapshots)
   
   **Use cases**:
   - Complete instance failure
   - Hardware failure
   - Accidental instance termination
   - Full system restore including configs
   - Launch identical instance in different AZ
   
   **Restore time**: 15-30 minutes (medium)
   **Restore scope**: Full instance

## Cost Breakdown (Production Example: t3.small + 50GB)

### MySQL Backups (S3):
- Compressed backup size: ~5-10 GB (assuming 50% compression)
- Hourly backups × 14 days retention = ~168 backups
- Average daily unique data: ~2 GB
- Total storage: ~28 GB
- **Cost**: ~$0.64/month

### EBS Snapshots:
- Initial snapshot: 50 GB
- Incremental snapshots (daily): ~2-5 GB per day average
- 14 days × 3 GB average = ~42 GB additional
- Total snapshot storage: ~50 GB + 42 GB = 92 GB
- **Cost**: ~$4.60/month

**Total Backup Cost**: ~$5.24/month for comprehensive protection

## Recommended Configurations

### Development/Staging:
```hcl
enable_automated_backups = true
backup_schedule          = "0 2 * * *"  # Daily at 2 AM
backup_retention_days    = 7
enable_ebs_snapshots     = false  # Optional, costs extra
```
**Cost**: ~$0.32/month (S3 only)

### Production:
```hcl
enable_automated_backups     = true
backup_schedule              = "0 * * * *"  # Hourly
backup_retention_days        = 14
enable_ebs_snapshots         = true
ebs_snapshot_interval_hours  = 24
ebs_snapshot_retention_count = 14
```
**Cost**: ~$5.24/month (S3 + EBS snapshots)

### Critical Production:
```hcl
enable_automated_backups     = true
backup_schedule              = "0 * * * *"  # Hourly
backup_retention_days        = 30
enable_ebs_snapshots         = true
ebs_snapshot_interval_hours  = 12  # Twice daily
ebs_snapshot_retention_count = 30
```
**Cost**: ~$15-20/month (extended retention + more frequent snapshots)

## Recovery Time Objectives (RTO)

| Scenario | Using MySQL Backup | Using EBS Snapshot |
|----------|-------------------|-------------------|
| Single table corrupted | 5 mins | 30 mins (full restore) |
| Database corrupted | 10 mins | 30 mins |
| EC2 instance failed | 30 mins (new EC2 + restore) | 20 mins (launch from snapshot) |
| Complete AZ failure | 30 mins (new EC2 + S3 restore) | 25 mins (snapshot to new AZ) |
| Configuration lost | 60 mins (manual reconfig) | 20 mins (snapshot has configs) |

## Best Practices

✅ **Enable both backup types in production** for maximum flexibility
✅ **Test restores regularly** (monthly recommended)
✅ **Monitor backup success** via CloudWatch logs
✅ **Tag snapshots** for compliance and auditing
✅ **Consider cross-region replication** for critical data
✅ **Document restore procedures** for your team
✅ **Automate restore testing** in non-prod environments

## Monitoring Backup Health

### MySQL Backups (S3):
```bash
# Check last backup
tail -20 /var/log/mysql-backup.log

# Verify S3 uploads
aws s3 ls s3://bucket/mysql-backups/env/project/ --recursive | tail -20

# Test restore (in staging)
aws s3 cp s3://bucket/mysql-backups/.../latest.sql.gz /tmp/
gunzip /tmp/latest.sql.gz
docker exec mysql-server mysql -u root -p < /tmp/latest.sql
```

### EBS Snapshots:
```bash
# List recent snapshots
aws ec2 describe-snapshots \
  --filters "Name=tag:Purpose,Values=MySQL-EBS-Backup" \
  --query 'Snapshots[*].[SnapshotId,StartTime,State,Progress]' \
  --output table

# Check DLM policy status
aws dlm get-lifecycle-policy --policy-id <policy-id>
```

## Security Considerations

🔒 **S3 Backups**:
- Encrypted at rest (AES-256)
- Versioning enabled
- Lifecycle policies for retention
- IAM permissions: EC2 can only write, not delete

🔒 **EBS Snapshots**:
- Encrypted by default (if source volume encrypted)
- Tagged with metadata
- Managed by DLM (automatic cleanup)
- IAM permissions: DLM has minimal required permissions

## Summary

The dual-backup strategy provides:
- **Fast recovery** for database issues (MySQL backups)
- **Complete recovery** for infrastructure failures (EBS snapshots)
- **Cost-effective** incremental backups
- **Automated** with no manual intervention
- **Secure** with encryption and IAM controls
- **Flexible** with configurable schedules and retention

**Bottom line**: You're now protected against both database-level and infrastructure-level failures! 🛡️

# EC2 MySQL Backup Strategy

This module provides **two layers of backup protection** for comprehensive disaster recovery.

## Backup Types

### 1️⃣ MySQL Database Backups (S3)

**Technology**: mysqldump + gzip → S3  
**What's backed up**: MySQL databases only (logical backup)  
**Frequency**: Hourly (default: `0 * * * *`)  
**Retention**: 7 days (configurable)  
**Cost**: ~$0.023/GB/month (S3 Standard)

**Use cases**:
- Database corruption
- Accidental data deletion
- Table/row recovery
- Cross-region disaster recovery
- Point-in-time recovery (hourly granularity)

**Restore time**: 5-15 minutes (fast)  
**Restore scope**: Database level

### 2️⃣ EBS Volume Snapshots (AWS DLM)

**Technology**: AWS Data Lifecycle Manager (block-level snapshots)  
**What's backed up**: Entire EBS volume (OS + Docker + MySQL + configs)  
**Frequency**: Daily at 3 AM UTC (default)  
**Retention**: 7 snapshots (configurable)  
**Cost**: ~$0.05/GB/month (incremental snapshots)

**Use cases**:
- Complete instance failure
- Hardware failure
- Accidental instance termination
- Full system restore including configs
- Launch identical instance in different AZ

**Restore time**: 15-30 minutes (medium)  
**Restore scope**: Full instance

## Recommended Configurations

### Development/Staging:
```hcl
enable_automated_backups = true
backup_schedule          = "0 2 * * *"  # Daily at 2 AM
backup_retention_days    = 7
enable_ebs_snapshots     = false  # Optional, costs extra
```
**Cost**: ~$0.32/month (S3 only)

### Production:
```hcl
enable_automated_backups     = true
backup_schedule              = "0 * * * *"  # Hourly
backup_retention_days        = 14
enable_ebs_snapshots         = true
ebs_snapshot_interval_hours  = 24
ebs_snapshot_retention_count = 14
enable_termination_protection = true  # Prevent accidents
```
**Cost**: ~$5.24/month (S3 + EBS snapshots)

## Frequently Asked Questions (FAQ)

### Q: Does `delete_on_termination = true` delete my EBS snapshots?

**A: No! Snapshots are completely independent.**

- **EBS Volume**: Deleted when instance terminates (if `delete_on_termination = true`)
- **EBS Snapshots**: **Persist forever** regardless of volume or instance state
- **Why it's safe**: Snapshots are stored separately in AWS, not tied to the volume lifecycle

```
Terminating Instance:
  EC2 Instance → ❌ Deleted
  EBS Volume   → ❌ Deleted (delete_on_termination = true)
  Snapshots    → ✅ Still exist! Can restore anytime
```

**Visual Explanation:**
```
EC2 Instance
  └── EBS Volume (delete_on_termination = true)
        ├── Snapshot 1 (independent, persists)
        ├── Snapshot 2 (independent, persists)
        └── Snapshot 3 (independent, persists)

[Terminate EC2]
  → EC2 Instance: ❌ Deleted
  → EBS Volume: ❌ Deleted
  → Snapshots: ✅ Still exist! Restore anytime
```

┌─────────────────────────────────────────────────────────┐
│  EC2 Instance (id: i-abc123)                            │
│  ├─ Status: Running                                     │
│  └─ EBS Volume (vol-xyz789) ← delete_on_termination=true│
│       ├─ Size: 50 GB                                    │
│       └─ Data: MySQL database                           │
└─────────────────────────────────────────────────────────┘
│
│ DLM takes snapshots
▼
┌─────────────────────────────────────────────────────────┐
│  EBS Snapshots (stored separately in AWS)               │
│  ├─ snap-001 (Jan 15) ← Independent                     │
│  ├─ snap-002 (Jan 16) ← Independent                     │
│  ├─ snap-003 (Jan 17) ← Independent                     │
│  └─ snap-004 (Jan 18) ← Independent                     │
└─────────────────────────────────────────────────────────┘

❌ TERMINATE INSTANCE
↓
┌─────────────────────────────────────────────────────────┐
│  EC2 Instance: ❌ DELETED                                │
│  EBS Volume:   ❌ DELETED (delete_on_termination=true)   │
└─────────────────────────────────────────────────────────┘

BUT...

✅ SNAPSHOTS STILL EXIST!
┌─────────────────────────────────────────────────────────┐
│  EBS Snapshots (still in AWS, ready to restore)         │
│  ├─ snap-001 (Jan 15) ✅ Available                      │
│  ├─ snap-002 (Jan 16) ✅ Available                      │
│  ├─ snap-003 (Jan 17) ✅ Available                      │
│  └─ snap-004 (Jan 18) ✅ Available                      │
└─────────────────────────────────────────────────────────┘


### Q: What happens if I accidentally delete the EC2 instance?

**A: Your data is safe in snapshots AND S3 backups.**

Recovery options:
1. **From EBS snapshot**: Launch new EC2 from latest snapshot (15-30 min)
2. **From S3 backup**: Launch new EC2, restore MySQL dump from S3 (20-40 min)

Enable termination protection in production:
```hcl
enable_termination_protection = true  # Prevents accidental deletion
```

### Q: How long are snapshots retained?

**A: Based on your configuration.**

- **Retention count**: `ebs_snapshot_retention_count = 7` (default)
- **Automatic cleanup**: DLM deletes snapshots older than retention count
- **Manual snapshots**: Never auto-deleted (create via AWS Console/CLI)

### Q: Can I restore individual files from EBS snapshots?

**A: Not directly - snapshots restore the entire volume.**

For file-level restore:
1. Create volume from snapshot
2. Attach to temporary EC2 instance
3. Mount volume and copy files
4. Transfer to production instance

For database-level restore, use S3 MySQL backups instead (faster).

### Q: What if both S3 and EBS fail?

**A: Extremely unlikely, but plan for it:**

Best practices:
- ✅ **Enable both backup types** (different failure domains)
- ✅ **Test restores monthly** (validate backups work)
- ✅ **Cross-region replication** for critical data (S3 + snapshot copy)
- ✅ **Monitor backup success** (CloudWatch alarms)
- ✅ **Document procedures** (runbooks for your team)

AWS provides 99.999999999% (11 nines) durability for both S3 and snapshots.

### Q: Should I enable termination protection?

**A: Recommended for production databases.**

```hcl
# Development/Staging
enable_termination_protection = false  # Easy to rebuild

# Production
enable_termination_protection = true   # Prevent accidents
```

Note: Termination protection prevents console/API deletion, but Terraform can still destroy (by design).

## Security Considerations

🔒 **S3 Backups**:
- Encrypted at rest (AES-256)
- Versioning enabled
- Lifecycle policies for retention
- IAM permissions: EC2 can only write, not delete

🔒 **EBS Snapshots**:
- Encrypted by default (if source volume encrypted)
- Tagged with metadata
- Managed by DLM (automatic cleanup)
- IAM permissions: DLM has minimal required permissions

## Summary

The dual-backup strategy provides:
- **Fast recovery** for database issues (MySQL backups)
- **Complete recovery** for infrastructure failures (EBS snapshots)
- **Cost-effective** incremental backups
- **Automated** with no manual intervention
- **Secure** with encryption and IAM controls
- **Flexible** with configurable schedules and retention
- **Safe deletion**: `delete_on_termination = true` is safe - snapshots persist

**Bottom line**: You're protected against both database-level and infrastructure-level failures! 🛡️

