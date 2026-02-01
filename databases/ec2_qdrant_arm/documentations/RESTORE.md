# Qdrant Snapshot Restoration Guide

## Overview

This guide explains how to restore Qdrant vector database from S3 backups created by the automated backup system.

---

## 📦 Backup Structure

Backups are stored in S3 with the following structure:

```
s3://{env}-{project}-{base_name}-backups/
└── YYYY-MM-DD/
    └── HHMMSS-qdrant-snapshot.tar.gz
```

**Example:**
```
s3://production-myapp-qdrant-backups/
├── 2026-02-01/
│   ├── 000001-qdrant-snapshot.tar.gz
│   ├── 060001-qdrant-snapshot.tar.gz
│   ├── 120001-qdrant-snapshot.tar.gz
│   └── 180001-qdrant-snapshot.tar.gz
└── 2026-02-02/
    └── 000001-qdrant-snapshot.tar.gz
```

---

## 🔄 Restoration Methods

### Method 1: Manual Restoration (Recommended for Testing)

Use this method when you want full control over the restoration process.

#### Step 1: Connect to EC2 Instance

```bash
# Via AWS Systems Manager Session Manager (no SSH needed)
aws ssm start-session --target i-xxxxxxxxxxxxxxxxx --region eu-west-2
```

#### Step 2: Stop Qdrant Service

```bash
sudo systemctl stop qdrant
```

#### Step 3: Download Backup from S3

```bash
# List available backups
aws s3 ls s3://{bucket-name}/ --recursive --human-readable

# Example: List today's backups
aws s3 ls s3://production-myapp-qdrant-backups/2026-02-01/ --human-readable

# Download specific backup
aws s3 cp s3://production-myapp-qdrant-backups/2026-02-01/120001-qdrant-snapshot.tar.gz /tmp/
```

#### Step 4: Extract Snapshot

```bash
# Create temporary extraction directory
mkdir -p /tmp/qdrant-restore

# Extract backup
cd /tmp
tar -xzf 120001-qdrant-snapshot.tar.gz -C /tmp/qdrant-restore

# Verify snapshot file exists
ls -lh /tmp/qdrant-restore/*.snapshot
```

#### Step 5: Restore Snapshot to Qdrant

```bash
# Option A: Replace entire storage (DESTRUCTIVE - deletes all existing data)
sudo systemctl stop qdrant
sudo rm -rf /var/lib/qdrant/storage/*
sudo cp /tmp/qdrant-restore/*.snapshot /var/lib/qdrant/snapshots/
sudo chown -R qdrant:qdrant /var/lib/qdrant/snapshots
sudo systemctl start qdrant

# Wait for Qdrant to start
sleep 10

# Restore from snapshot via API
QDRANT_API_KEY=$(sudo cat /etc/qdrant/qdrant.env | grep QDRANT__SERVICE__API_KEY | cut -d'=' -f2)
SNAPSHOT_NAME=$(basename /var/lib/qdrant/snapshots/*.snapshot)

curl -X POST "http://localhost:6333/collections/{collection_name}/snapshots/$SNAPSHOT_NAME/recover" \
  -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json"
```

```bash
# Option B: Restore specific collection (NON-DESTRUCTIVE - preserves other collections)
# Copy snapshot to snapshots directory
sudo cp /tmp/qdrant-restore/*.snapshot /var/lib/qdrant/snapshots/
sudo chown -R qdrant:qdrant /var/lib/qdrant/snapshots

# Get API key
QDRANT_API_KEY=$(sudo cat /etc/qdrant/qdrant.env | grep QDRANT__SERVICE__API_KEY | cut -d'=' -f2)
SNAPSHOT_NAME=$(basename /var/lib/qdrant/snapshots/*.snapshot)

# Restore specific collection from snapshot
curl -X POST "http://localhost:6333/collections/{collection_name}/snapshots/$SNAPSHOT_NAME/recover" \
  -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "location": "file:///var/lib/qdrant/snapshots/'"$SNAPSHOT_NAME"'"
  }'
```

#### Step 6: Verify Restoration

```bash
# Check Qdrant status
sudo systemctl status qdrant

# Verify collections
curl -X GET "http://localhost:6333/collections" \
  -H "api-key: $QDRANT_API_KEY"

# Check collection stats
curl -X GET "http://localhost:6333/collections/{collection_name}" \
  -H "api-key: $QDRANT_API_KEY"
```

#### Step 7: Cleanup

```bash
# Remove temporary files
rm -rf /tmp/qdrant-restore /tmp/*.tar.gz
```

---

### Method 2: Automated Restoration Script

Use this for faster restoration in production scenarios.

#### Create Restoration Script

```bash
sudo tee /usr/local/bin/restore_qdrant.sh > /dev/null <<'RESTORESCRIPT'
#!/bin/bash
set -e

# Usage: ./restore_qdrant.sh <s3-backup-path> [collection-name]
# Example: ./restore_qdrant.sh s3://bucket/2026-02-01/120001-qdrant-snapshot.tar.gz my_collection

if [ -z "$1" ]; then
  echo "Usage: $0 <s3-backup-path> [collection-name]"
  echo "Example: $0 s3://bucket/2026-02-01/120001-qdrant-snapshot.tar.gz my_collection"
  exit 1
fi

S3_BACKUP_PATH=$1
COLLECTION_NAME=$2
TEMP_DIR="/tmp/qdrant-restore-$(date +%s)"
SNAPSHOT_DIR="/var/lib/qdrant/snapshots"

echo "=== Qdrant Restoration Started at $(date) ==="
echo "Backup: $S3_BACKUP_PATH"

# Download backup from S3
echo "Downloading backup from S3..."
mkdir -p $TEMP_DIR
aws s3 cp $S3_BACKUP_PATH $TEMP_DIR/backup.tar.gz

# Extract snapshot
echo "Extracting snapshot..."
tar -xzf $TEMP_DIR/backup.tar.gz -C $TEMP_DIR

# Find snapshot file
SNAPSHOT_FILE=$(ls $TEMP_DIR/*.snapshot | head -1)
if [ -z "$SNAPSHOT_FILE" ]; then
  echo "ERROR: No snapshot file found in backup"
  rm -rf $TEMP_DIR
  exit 1
fi

SNAPSHOT_NAME=$(basename $SNAPSHOT_FILE)

# Copy snapshot to Qdrant snapshots directory
echo "Copying snapshot to Qdrant directory..."
sudo cp $SNAPSHOT_FILE $SNAPSHOT_DIR/
sudo chown qdrant:qdrant $SNAPSHOT_DIR/$SNAPSHOT_NAME

# Get API key
QDRANT_API_KEY=$(sudo cat /etc/qdrant/qdrant.env | grep QDRANT__SERVICE__API_KEY | cut -d'=' -f2)

if [ -n "$COLLECTION_NAME" ]; then
  # Restore specific collection
  echo "Restoring collection: $COLLECTION_NAME"
  curl -X POST "http://localhost:6333/collections/$COLLECTION_NAME/snapshots/$SNAPSHOT_NAME/recover" \
    -H "api-key: $QDRANT_API_KEY" \
    -H "Content-Type: application/json"
else
  # Full restore (requires Qdrant restart)
  echo "Performing full restore (all collections)..."
  echo "Stopping Qdrant..."
  sudo systemctl stop qdrant
  
  echo "Clearing existing storage..."
  sudo rm -rf /var/lib/qdrant/storage/*
  
  echo "Starting Qdrant..."
  sudo systemctl start qdrant
  sleep 10
  
  echo "Restoring from snapshot..."
  curl -X POST "http://localhost:6333/snapshots/$SNAPSHOT_NAME/recover" \
    -H "api-key: $QDRANT_API_KEY"
fi

# Cleanup
echo "Cleaning up temporary files..."
rm -rf $TEMP_DIR

echo "=== Restoration completed at $(date) ==="
echo "Verifying collections..."
curl -X GET "http://localhost:6333/collections" -H "api-key: $QDRANT_API_KEY"
RESTORESCRIPT

sudo chmod +x /usr/local/bin/restore_qdrant.sh
```

#### Run Restoration Script

```bash
# Restore specific collection (non-destructive)
sudo /usr/local/bin/restore_qdrant.sh \
  s3://production-myapp-qdrant-backups/2026-02-01/120001-qdrant-snapshot.tar.gz \
  my_collection

# Full restore (destructive - replaces all data)
sudo /usr/local/bin/restore_qdrant.sh \
  s3://production-myapp-qdrant-backups/2026-02-01/120001-qdrant-snapshot.tar.gz
```

---

## 🚨 Disaster Recovery Scenarios

### Scenario 1: Accidental Data Deletion (Single Collection)

**Problem:** Accidentally deleted vectors from a collection.

**Solution:** Restore only that collection from the most recent backup.

```bash
# Find latest backup
LATEST_BACKUP=$(aws s3 ls s3://bucket/$(date +%Y-%m-%d)/ --recursive | tail -1 | awk '{print $4}')

# Restore collection
sudo /usr/local/bin/restore_qdrant.sh s3://bucket/$LATEST_BACKUP my_collection
```

---

### Scenario 2: Complete Data Loss (Instance Failure)

**Problem:** EC2 instance terminated, EBS volume lost, all data gone.

**Solution:** Launch new instance from Terraform, then restore from S3.

```bash
# 1. Launch new instance via Terraform (automated)
cd terraform
terraform apply

# 2. Connect to new instance
aws ssm start-session --target i-xxxxxxxxxxxxxxxxx

# 3. Find yesterday's last backup (today's instance has no backups yet)
YESTERDAY=$(date -d yesterday +%Y-%m-%d)
LATEST_BACKUP=$(aws s3 ls s3://bucket/$YESTERDAY/ --recursive | tail -1 | awk '{print $4}')

# 4. Restore all data
sudo /usr/local/bin/restore_qdrant.sh s3://bucket/$LATEST_BACKUP
```

---

### Scenario 3: Corrupted Database

**Problem:** Database corruption detected, Qdrant won't start.

**Solution:** Full restore from last known good backup.

```bash
# 1. Identify last known good backup (e.g., 2 hours ago)
GOOD_BACKUP="2026-02-01/100001-qdrant-snapshot.tar.gz"

# 2. Stop corrupted instance
sudo systemctl stop qdrant

# 3. Restore from known good backup
sudo /usr/local/bin/restore_qdrant.sh s3://bucket/$GOOD_BACKUP

# 4. Verify restoration
curl -X GET "http://localhost:6333/collections" -H "api-key: $QDRANT_API_KEY"
```

---

### Scenario 4: Point-in-Time Recovery

**Problem:** Need to restore data to a specific point in time (e.g., before a bad deployment).

**Solution:** Restore from backup closest to desired time.

```bash
# List backups for specific date
aws s3 ls s3://bucket/2026-02-01/ --human-readable

# Find backup closest to desired time (e.g., 12:00 PM = 120001)
# Backups run hourly at :00:01 (000001, 010001, 020001, etc.)

# Restore from 12:00 PM backup
sudo /usr/local/bin/restore_qdrant.sh \
  s3://bucket/2026-02-01/120001-qdrant-snapshot.tar.gz
```

---

## 🧪 Testing Restoration (Best Practice)

**Always test restoration in non-production environment first!**

```bash
# 1. Launch test instance
cd terraform/staging
terraform apply -var="env=test"

# 2. Connect to test instance
aws ssm start-session --target i-test-xxxxxxxxx

# 3. Restore production backup to test instance
sudo /usr/local/bin/restore_qdrant.sh \
  s3://production-bucket/2026-02-01/120001-qdrant-snapshot.tar.gz

# 4. Verify data integrity
curl -X GET "http://localhost:6333/collections" -H "api-key: $QDRANT_API_KEY"

# 5. Run application tests
# ... your application-specific tests ...

# 6. If successful, proceed with production restoration
```

---

## 📊 Backup Retention Policy

Backups are managed via S3 lifecycle policies (configured in Terraform):

| Age | Storage Class | Status |
|-----|---------------|--------|
| 0-7 days | Standard | Active |
| 8-30 days | Intelligent-Tiering | Archived |
| 31-90 days | Glacier Instant Retrieval | Deep Archive |
| 90+ days | Deleted | Removed |

**Recovery Time:**
- Standard (0-7 days): Immediate
- Intelligent-Tiering (8-30 days): Immediate
- Glacier (31-90 days): Minutes to hours

---

## ⚠️ Important Notes

### Snapshot Compatibility
- Qdrant snapshots are **forward-compatible** (older snapshots work on newer Qdrant versions)
- Qdrant snapshots are **NOT backward-compatible** (newer snapshots may not work on older versions)
- Always restore to same or newer Qdrant version

### Data Consistency
- Snapshots are created using Qdrant's native snapshot API
- Snapshots are **consistent** (point-in-time, transactionally safe)
- No need to stop Qdrant during backup creation

### Collection-Level Restoration
- You can restore individual collections without affecting others
- Useful for selective rollbacks
- Less risky than full restoration

### Full Restoration
- **Destructive operation** - deletes all existing data
- Only use when necessary (complete data loss, corruption)
- Always test in non-production first

---

## 🔍 Troubleshooting

### Issue: "Snapshot not found"

```bash
# Verify snapshot was downloaded correctly
ls -lh /var/lib/qdrant/snapshots/*.snapshot

# Check permissions
sudo chown -R qdrant:qdrant /var/lib/qdrant/snapshots
sudo chmod 644 /var/lib/qdrant/snapshots/*.snapshot
```

### Issue: "API key authentication failed"

```bash
# Verify API key is set correctly
sudo cat /etc/qdrant/qdrant.env

# Reload systemd if you changed the env file
sudo systemctl daemon-reload
sudo systemctl restart qdrant
```

### Issue: "Cannot connect to Qdrant API"

```bash
# Check Qdrant status
sudo systemctl status qdrant

# Check logs
sudo journalctl -u qdrant -f

# Verify Qdrant is listening
curl http://localhost:6333/
```

### Issue: "Restoration hangs or times out"

```bash
# Check disk space
df -h /var/lib/qdrant

# Check Qdrant logs for errors
sudo tail -f /var/log/qdrant/qdrant.log

# Verify snapshot is not corrupted
tar -tzf backup.tar.gz
```

---

## 📞 Support

For assistance with restoration:

1. Check Qdrant logs: `sudo journalctl -u qdrant -f`
2. Verify S3 backup exists: `aws s3 ls s3://bucket/`
3. Review this documentation
4. Contact DevOps team if issues persist

---

## ✅ Restoration Checklist

Before restoring:
- [ ] Identify correct backup (date/time)
- [ ] Verify backup exists in S3
- [ ] Test restoration in non-production environment
- [ ] Notify team of planned restoration
- [ ] Document reason for restoration

During restoration:
- [ ] Stop application connections to Qdrant
- [ ] Follow restoration steps carefully
- [ ] Monitor logs for errors

After restoration:
- [ ] Verify all collections restored
- [ ] Check vector counts match expected values
- [ ] Run application health checks
- [ ] Resume normal operations
- [ ] Document restoration in incident log

---

**Last Updated:** February 1, 2026  
**Module Version:** ec2_qdrant_arm v1.0  
**Qdrant Version:** 1.12.5+

