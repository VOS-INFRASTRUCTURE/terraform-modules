# EBS Snapshots Guide - Volume vs Instance Snapshots

## Overview

AWS provides **two types of EBS snapshots**:
1. **Volume Snapshots** - Snapshot individual EBS volumes
2. **Instance Snapshots** - Snapshot all volumes attached to an EC2 instance (multi-volume)

This module currently implements **Volume Snapshots** via AWS Data Lifecycle Manager (DLM).

---

## Table of Contents

1. [Current Implementation](#current-implementation)
2. [Volume Snapshots vs Instance Snapshots](#volume-snapshots-vs-instance-snapshots)
3. [What the Module Does](#what-the-module-does)
4. [When to Use Each Type](#when-to-use-each-type)
5. [How to Create Manual Snapshots](#how-to-create-manual-snapshots)
6. [Restore from Snapshots](#restore-from-snapshots)
7. [Cost Comparison](#cost-comparison)

---

## Current Implementation

### What `ebs_snapshots.tf` Does

The module uses **AWS Data Lifecycle Manager (DLM)** to create automated **volume snapshots**:

```terraform
resource "aws_dlm_lifecycle_policy" "mysql_ebs_snapshots" {
  policy_details {
    resource_types = ["VOLUME"]  # ← Volume snapshots, not instance
    
    target_tags = {
      Name = "${local.instance_name}-root"  # Targets root volume only
    }
    
    schedule {
      create_rule {
        interval      = 24           # Daily
        interval_unit = "HOURS"
        times         = ["03:00"]    # 3 AM UTC
      }
      
      retain_rule {
        count = 7  # Keep 7 snapshots
      }
    }
  }
}
```

**What gets backed up:**
- ✅ Root EBS volume only (`/dev/sda1` or `/dev/xvda`)
- ❌ Additional data volumes (if any) - NOT included

---

## Volume Snapshots vs Instance Snapshots

### Volume Snapshots (Current Implementation)

```
┌─────────────────────────────────────┐
│      EC2 Instance                   │
│                                     │
│  ┌──────────────────────────────┐   │
│  │  Root Volume (20 GB)         │───┼──► Snapshot 1 (Root)
│  │  /dev/xvda                   │   │    Snapshot 2 (Root)
│  │  OS + Docker + MySQL         │   │    Snapshot 3 (Root)
│  └──────────────────────────────┘   │
│                                     │
│  ┌──────────────────────────────┐   │
│  │  Data Volume (100 GB)        │   │    ❌ Not snapshotted
│  │  /dev/xvdb                   │   │       (if exists)
│  │  /data                       │   │
│  └──────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

**Characteristics:**
- Snapshots ONE volume at a time
- Managed by DLM (automated)
- Tag-based targeting
- Separate snapshots for each volume

---

### Instance Snapshots (Multi-Volume)

```
┌─────────────────────────────────────┐
│      EC2 Instance                   │
│      i-085c61e29bc2a6034            │◄─── Instance ID
│                                     │
│  ┌──────────────────────────────┐   │
│  │  Root Volume (20 GB)         │───┼──► Snapshot Set 1:
│  │  /dev/xvda                   │   │     - Root snapshot
│  └──────────────────────────────┘   │     - Data snapshot
│                                     │     (Crash-consistent)
│  ┌──────────────────────────────┐   │
│  │  Data Volume (100 GB)        │───┼──►
│  │  /dev/xvdb                   │   │
│  └──────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

**Characteristics:**
- Snapshots ALL volumes at once
- Crash-consistent (point-in-time)
- Instance ID targeting
- Grouped snapshots with same timestamp

---

### Comparison Table

| Feature | Volume Snapshots (DLM) | Instance Snapshots |
|---------|------------------------|-------------------|
| **What's Snapshotted** | Single volume | All volumes on instance |
| **Consistency** | Per-volume | Crash-consistent across all volumes |
| **Targeting** | Volume tags | Instance ID |
| **Automation** | DLM policy | Manual or DLM (newer) |
| **Terraform Support** | ✅ `aws_dlm_lifecycle_policy` | ⚠️ Limited (use volume method) |
| **Use Case** | Simple instances, single volume | Multi-volume databases, complex apps |
| **Root Volume** | ✅ Yes | ✅ Yes |
| **Data Volumes** | ❌ Each needs separate policy | ✅ All included automatically |
| **Exclude Volumes** | N/A (tag-based) | ✅ Can exclude root or specific volumes |
| **Copy Tags** | ✅ Yes | ✅ Yes |

---

## What the Module Does

### Current Behavior

When you enable EBS snapshots in the MySQL module:

```hcl
module "mysql_db" {
  source = "../../databases/ec2_mysql"
  
  # ... other config ...
  
  enable_ebs_snapshots        = true
  ebs_snapshot_interval_hours = 24
  ebs_snapshot_time           = "03:00"
  ebs_snapshot_retention_count = 7
}
```

**Result:**
1. ✅ DLM policy created
2. ✅ Daily snapshots at 3 AM UTC
3. ✅ Root volume snapshotted
4. ✅ 7 snapshots retained
5. ✅ Older snapshots auto-deleted

**What's Included:**
- Root EBS volume (20 GB default)
- Everything on root: OS, Docker, MySQL data (in `/home/ubuntu/mysql_data`)

**What's NOT Included:**
- Additional EBS volumes (if you add any)

---

## When to Use Each Type

### Use Volume Snapshots (Current) When:

✅ **Single volume instance** (like this MySQL module)  
✅ **Root volume contains everything** (OS + app + data)  
✅ **Want automated DLM management**  
✅ **Simple restore process**  
✅ **Cost-conscious** (only snapshot what you need)  

**Example:** This MySQL module stores everything on the root volume, so volume snapshots are sufficient.

---

### Use Instance Snapshots When:

✅ **Multiple EBS volumes** attached to instance  
✅ **Separate data volumes** (e.g., `/dev/xvdb` for data)  
✅ **Need crash-consistent** snapshots across volumes  
✅ **Complex applications** (databases with separate log volumes)  
✅ **Want all-or-nothing** backup  

**Example:** Production database with:
- Root volume: OS + binaries
- Data volume 1: MySQL data
- Data volume 2: MySQL logs

---

## How to Create Manual Snapshots

### Method 1: Volume Snapshot (Single Volume)

#### Via AWS Console:
1. Go to **EC2 Console** → **Volumes**
2. Select the volume (filter by instance name)
3. Click **Actions** → **Create snapshot**
4. Add description: `manual-backup-2026-01-20`
5. Add tags
6. Click **Create snapshot**

#### Via AWS CLI:
```bash
# Get volume ID
VOLUME_ID=$(aws ec2 describe-volumes \
  --filters "Name=tag:Name,Values=*mysql*" \
  --query 'Volumes[0].VolumeId' \
  --output text)

# Create snapshot
aws ec2 create-snapshot \
  --volume-id $VOLUME_ID \
  --description "Manual MySQL backup $(date +%Y-%m-%d)" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=mysql-manual-backup},{Key=Type,Value=Manual}]'
```

---

### Method 2: Instance Snapshot (Multi-Volume)

#### Via AWS Console:
1. Go to **EC2 Console** → **Instances**
2. Select your instance (e.g., `i-085c61e29bc2a6034`)
3. Click **Actions** → **Image and templates** → **Create image**
4. Or: **Storage** → **Create snapshot** → Choose "Instance"
5. **Instance ID**: Auto-filled
6. **Description**: `Multi-volume backup 2026-01-20`
7. **Encryption**: Already encrypted (inherits from volume)
8. **Exclude volumes**:
   - ☐ Exclude root volume
   - ☐ Exclude specific data volumes
9. **Copy tags from source volume**: ✅ Checked
10. **Tags**: Add custom tags
11. Click **Create snapshot**

#### Via AWS CLI:
```bash
# Instance snapshot (all volumes)
aws ec2 create-snapshots \
  --instance-specification InstanceId=i-085c61e29bc2a6034 \
  --description "Multi-volume MySQL backup $(date +%Y-%m-%d)" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=mysql-instance-backup},{Key=Type,Value=Instance}]'

# Exclude root volume
aws ec2 create-snapshots \
  --instance-specification InstanceId=i-085c61e29bc2a6034 \
  --exclude-boot-volume \
  --description "Data volumes only"

# Exclude specific data volume
aws ec2 create-snapshots \
  --instance-specification InstanceId=i-085c61e29bc2a6034,ExcludeDataVolumeIds=vol-0cb5ae87920047a32
```

---

## Restore from Snapshots

### Restore Volume Snapshot

#### Option 1: Create Volume from Snapshot

```bash
# List snapshots
aws ec2 describe-snapshots \
  --filters "Name=tag:Purpose,Values=MySQL-EBS-Backup" \
  --query 'Snapshots[*].[SnapshotId,StartTime,VolumeSize]' \
  --output table

# Create volume from snapshot
aws ec2 create-volume \
  --snapshot-id snap-0123456789abcdef \
  --availability-zone eu-west-2a \
  --volume-type gp3 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=mysql-restored}]'

# Attach to instance
aws ec2 attach-volume \
  --volume-id vol-NEW-VOLUME-ID \
  --instance-id i-NEW-INSTANCE-ID \
  --device /dev/xvdf

# Mount on instance
sudo mkdir -p /mnt/restored
sudo mount /dev/xvdf /mnt/restored
```

---

#### Option 2: Launch New Instance from Snapshot

```bash
# Create AMI from snapshot
aws ec2 register-image \
  --name "mysql-restore-$(date +%Y%m%d)" \
  --architecture x86_64 \
  --root-device-name /dev/xvda \
  --block-device-mappings \
    "DeviceName=/dev/xvda,Ebs={SnapshotId=snap-0123456789abcdef,VolumeType=gp3}"

# Launch instance from AMI
# (Use Terraform or AWS Console)
```

---

### Restore Instance Snapshot (Multi-Volume)

When you create instance snapshots, AWS creates multiple snapshots (one per volume) with the same timestamp:

```bash
# List instance snapshot set
aws ec2 describe-snapshots \
  --filters \
    "Name=tag:instance-id,Values=i-085c61e29bc2a6034" \
    "Name=start-time,Values=2026-01-20*" \
  --query 'Snapshots[*].[SnapshotId,VolumeId,VolumeSize,Description]' \
  --output table

# Create volumes from all snapshots
for snapshot in snap-001 snap-002 snap-003; do
  aws ec2 create-volume \
    --snapshot-id $snapshot \
    --availability-zone eu-west-2a \
    --volume-type gp3
done

# Attach all volumes to new instance
# Launch instance, then attach each volume
```

---

## Cost Comparison

### Volume Snapshots (Current)

**Scenario:** Single 20 GB root volume, 7 snapshots retained

```
Initial snapshot:  20 GB × $0.05/GB/month = $1.00/month
Incremental (avg): ~2 GB/day × 7 days = 14 GB
Incremental cost:  14 GB × $0.05/GB/month = $0.70/month

Total: ~$1.70/month
```

---

### Instance Snapshots (Multi-Volume)

**Scenario:** Root (20 GB) + Data volume (100 GB), 7 snapshots retained

```
Initial snapshots:
  Root:  20 GB × $0.05 = $1.00/month
  Data: 100 GB × $0.05 = $5.00/month
  
Incremental (avg):
  Root:  ~2 GB/day × 7 days = 14 GB → $0.70/month
  Data: ~10 GB/day × 7 days = 70 GB → $3.50/month

Total: ~$10.20/month
```

**Cost Factor:** Multi-volume snapshots cost more because they include all volumes.

---

## Summary

### Current Module Implementation

✅ **Volume Snapshots** (via DLM)  
✅ **Root volume only**  
✅ **Automated daily**  
✅ **7-day retention**  
✅ **~$1.70/month** (20 GB volume)  

### When to Switch to Instance Snapshots

Consider instance snapshots if you:
- Add additional EBS volumes
- Need crash-consistent multi-volume backups
- Separate data onto different volumes

### Current Setup is Perfect For:

✅ Single-volume MySQL instance  
✅ All data on root volume  
✅ Simple restore process  
✅ Cost-effective  

---

## Configuration Reference

### Current Variables

```hcl
variable "enable_ebs_snapshots" {
  description = "Enable automated EBS volume snapshots using AWS Data Lifecycle Manager"
  type        = bool
  default     = false
}

variable "ebs_snapshot_interval_hours" {
  description = "Interval in hours between EBS snapshots (12 or 24 recommended)"
  type        = number
  default     = 24
}

variable "ebs_snapshot_time" {
  description = "Time to take daily snapshots in UTC (HH:MM format)"
  type        = string
  default     = "03:00"
}

variable "ebs_snapshot_retention_count" {
  description = "Number of EBS snapshots to retain"
  type        = number
  default     = 7
}
```

### Example Usage

```hcl
module "mysql_prod" {
  source = "../../databases/ec2_mysql"
  
  # ... other config ...
  
  # Enable volume snapshots
  enable_ebs_snapshots        = true
  ebs_snapshot_interval_hours = 24      # Daily
  ebs_snapshot_time           = "03:00" # 3 AM UTC
  ebs_snapshot_retention_count = 14     # 2 weeks
}
```

---

## Related Documentation

- [AWS EBS Snapshots](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-snapshots.html)
- [Multi-Volume Snapshots](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-creating-snapshot.html#ebs-create-snapshot-multi-volume)
- [AWS Data Lifecycle Manager](https://docs.aws.amazon.com/ebs/latest/userguide/snapshot-lifecycle.html)
- [BACKUP_STRATEGY.md](../BACKUP_STRATEGY.md) - Complete backup strategy (S3 + EBS)

---

**Last Updated:** January 2026

