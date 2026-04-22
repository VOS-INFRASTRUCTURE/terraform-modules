# Monitoring WAL Growth for CDC – Sizing & Operational Guide

> This document covers how to monitor PostgreSQL WAL growth when using logical
> replication / CDC (Change Data Capture), how to size your disk correctly, and
> what to do when WAL grows out of control.

---

## Why WAL Growth is the #1 CDC Operational Risk

When you enable logical replication or wal2json CDC, PostgreSQL creates a
**replication slot** that tracks the consumer's read position (LSN).
PostgreSQL **will not delete WAL segments** until every active slot has
confirmed it has consumed them.

```
Normal flow (consumer healthy):
  WAL written → consumer reads → slot LSN advances → old WAL deleted ✅

Broken flow (consumer stopped/slow):
  WAL written → consumer STOPPED → slot LSN frozen → WAL accumulates ❌
                                                       Disk fills up
                                                       PostgreSQL CRASHES
                                                       (cannot write new WAL)
```

> ⚠️ A crashed PostgreSQL due to a full disk is a **complete outage**.
> It cannot recover until disk space is freed.

---

## 1. Key Metrics to Monitor

### 1.1 Replication Slot Lag (Most Important)

```sql
-- Show all slots with human-readable lag size and active status
SELECT
  slot_name,
  plugin,
  slot_type,
  active,
  active_pid,
  pg_size_pretty(
    pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)
  )                          AS retained_wal,
  pg_size_pretty(
    pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)
  )                          AS unconsumed_wal,
  restart_lsn,
  confirmed_flush_lsn
FROM pg_replication_slots
ORDER BY pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) DESC;
```

| Column              | Meaning                                                     |
|---------------------|-------------------------------------------------------------|
| `retained_wal`      | WAL kept on disk because of this slot (total)               |
| `unconsumed_wal`    | WAL the consumer has NOT yet processed                      |
| `active`            | `true` = consumer connected, `false` = consumer gone        |
| `active_pid`        | OS PID of the consumer process (NULL if inactive)           |

### 1.2 Total WAL Directory Size

```sql
-- Total size of all WAL files on disk
SELECT pg_size_pretty(sum(size)) AS total_wal_size
FROM pg_ls_waldir();

-- Individual WAL file count and average size
SELECT
  count(*)                    AS wal_file_count,
  pg_size_pretty(sum(size))   AS total_wal_size,
  pg_size_pretty(avg(size))   AS avg_wal_file_size
FROM pg_ls_waldir();
```

### 1.3 WAL Write Rate (Throughput)

```sql
-- WAL bytes written since last stats reset
SELECT
  pg_size_pretty(wal_bytes)          AS total_wal_written,
  wal_records,
  wal_fpi,                           -- full-page images (after checkpoints)
  stats_reset
FROM pg_stat_wal;

-- Current WAL LSN (use difference over time to measure write rate)
SELECT pg_current_wal_lsn();
-- Run again after 60 seconds and subtract to get bytes/sec
```

### 1.4 Checkpoint Activity

```sql
-- Checkpoint frequency (too frequent = too much WAL churn)
SELECT
  checkpoints_timed,
  checkpoints_req,                   -- forced checkpoints (sign of high WAL load)
  checkpoint_write_time,
  checkpoint_sync_time,
  buffers_checkpoint,
  stats_reset
FROM pg_stat_bgwriter;
```

### 1.5 Active Connections per Slot

```sql
-- Match slots to backend connections
SELECT
  r.slot_name,
  r.active,
  r.active_pid,
  a.application_name,
  a.client_addr,
  a.state,
  a.backend_start
FROM pg_replication_slots r
LEFT JOIN pg_stat_activity a ON a.pid = r.active_pid;
```

---

## 2. Alert Thresholds

Configure these alerts in CloudWatch, Prometheus, or your monitoring tool:

| Metric                         | Warning Threshold | Critical Threshold | Action                              |
|--------------------------------|-------------------|--------------------|-------------------------------------|
| Slot retained WAL              | > 2 GB            | > 5 GB             | Investigate consumer, consider drop |
| Slot `active = false`          | > 5 min           | > 15 min           | Restart consumer process            |
| WAL directory total size       | > 50% disk        | > 70% disk         | Expand disk or drop lagging slot    |
| Disk free space (`/var/lib/postgresql`) | < 30%  | < 15%              | Emergency: drop slot or expand disk |
| `checkpoints_req` rate         | Rising trend      | —                  | Tune `max_wal_size`                 |

### CloudWatch Disk Alarm Example (Terraform)

```hcl
resource "aws_cloudwatch_metric_alarm" "pgsql_disk_warning" {
  alarm_name          = "${var.env}-pgsql-disk-usage-warning"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Average"
  threshold           = 50   # % disk used – warning

  dimensions = {
    InstanceId = aws_instance.pgsql_ec2.id
    path       = "/var/lib/postgresql"
    fstype     = "ext4"
  }

  alarm_actions = [var.sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "pgsql_disk_critical" {
  alarm_name          = "${var.env}-pgsql-disk-usage-critical"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  period              = 60
  statistic           = "Average"
  threshold           = 70   # % disk used – critical

  dimensions = {
    InstanceId = aws_instance.pgsql_ec2.id
    path       = "/var/lib/postgresql"
    fstype     = "ext4"
  }

  alarm_actions = [var.sns_topic_arn]
}
```

---

## 3. Disk Sizing Guide for CDC Workloads

### 3.1 Factors That Drive WAL Volume

| Factor                        | Impact on WAL size                                     |
|-------------------------------|--------------------------------------------------------|
| Write rate (INSERTs/UPDATEs)  | Higher write rate = more WAL per second                |
| `REPLICA IDENTITY FULL`       | Logs entire old row on UPDATE/DELETE – can 2–5x WAL   |
| Number of active slots        | Each slot independently retains WAL until consumed     |
| Consumer lag (processing time)| Slow consumer = more WAL retained                     |
| `wal_level = logical`         | Slightly more WAL than `replica`                       |
| Bulk operations               | `COPY`, mass UPDATEs generate large WAL bursts         |

### 3.2 Sizing Formula

```
Minimum safe disk = data_size
                  + (peak_wal_write_rate_per_sec × max_acceptable_consumer_lag_sec × num_slots)
                  + wal_keep_size
                  + 20% safety buffer

Example:
  data_size              = 50 GB
  wal_write_rate         = 10 MB/sec (moderate write workload)
  max consumer lag       = 300 sec (5 min before alerting)
  num_slots              = 2
  wal_keep_size          = 1 GB

  WAL buffer needed = 10 MB/s × 300s × 2 slots = 6 GB
  Total disk        = 50 GB + 6 GB + 1 GB + ~11 GB (20%) = ~68 GB
  → Provision 80 GB EBS gp3
```

### 3.3 Measure Your Actual WAL Write Rate

Run this over a 5-minute window during peak load:

```sql
-- Step 1: Record start LSN
SELECT pg_current_wal_lsn() AS start_lsn;

-- Wait 300 seconds (5 minutes) ...

-- Step 2: Record end LSN and calculate rate
SELECT
  pg_size_pretty(
    pg_wal_lsn_diff(pg_current_wal_lsn(), 'PASTE_START_LSN_HERE'::pg_lsn)
  ) AS wal_generated_in_5min,
  pg_size_pretty(
    pg_wal_lsn_diff(pg_current_wal_lsn(), 'PASTE_START_LSN_HERE'::pg_lsn) / 300
  ) AS wal_bytes_per_sec;
```

### 3.4 Recommended EBS Volume Configuration

| Workload              | Data Size | WAL Buffer | Recommended EBS | IOPS    |
|-----------------------|-----------|------------|-----------------|---------|
| Low (< 1 MB/s WAL)    | < 20 GB   | 2 GB       | 30 GB gp3       | 3,000   |
| Medium (1–10 MB/s)    | 20–100 GB | 10 GB      | 150 GB gp3      | 6,000   |
| High (10–50 MB/s)     | 100+ GB   | 30 GB      | 300 GB gp3      | 12,000  |
| Very High (> 50 MB/s) | 100+ GB   | 100 GB     | 500 GB+ io2     | 16,000+ |

> 💡 gp3 allows you to set throughput up to 1,000 MB/s and IOPS up to 16,000
> independently of volume size — cheaper than gp2 for high-performance needs.

---

## 4. postgresql.conf Tuning for CDC

```ini
# ─── WAL Level ────────────────────────────────────────────────────────────────
# Must be logical for CDC / wal2json
wal_level = logical

# ─── Slot Limits ──────────────────────────────────────────────────────────────
# How many logical replication slots can exist simultaneously
max_replication_slots = 10

# How many WAL sender processes allowed (>= max_replication_slots)
max_wal_senders = 10

# ─── WAL Retention Safety Valve (PostgreSQL 13+) ─────────────────────────────
# Maximum WAL a single slot can retain before PostgreSQL auto-invalidates it.
# This PREVENTS disk-full crashes caused by dead consumers.
# Set to 10–25% of your disk (e.g., 10 GB on a 100 GB disk).
# ⚠️ When a slot is invalidated, the consumer must re-sync from scratch.
max_slot_wal_keep_size = 10GB

# ─── WAL Size Limits ──────────────────────────────────────────────────────────
# Maximum WAL size before a checkpoint is forced.
# Larger = fewer checkpoints = less I/O, but slower recovery.
# Rule: 2–4x checkpoint_completion_target window of write volume.
max_wal_size = 4GB
min_wal_size = 1GB

# Minimum WAL to retain regardless of slots (emergency buffer)
wal_keep_size = 1GB

# ─── Checkpoint Tuning ────────────────────────────────────────────────────────
# Target: complete checkpoint over this fraction of checkpoint_timeout
checkpoint_completion_target = 0.9

# How often a timed checkpoint occurs (default 5 min is often too frequent)
checkpoint_timeout = 10min

# ─── WAL Compression (PostgreSQL 15+) ─────────────────────────────────────────
# Reduces WAL size by ~50% for text-heavy workloads.
# Small CPU cost, significant disk/IO savings.
wal_compression = lz4
```

---

## 5. Monitoring Queries – Daily Operational Runbook

### 5.1 Morning Health Check

```sql
-- 1. Are all CDC slots active and caught up?
SELECT
  slot_name,
  active,
  pg_size_pretty(
    pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)
  ) AS lag
FROM pg_replication_slots;

-- 2. What is the current WAL directory size?
SELECT pg_size_pretty(sum(size)) FROM pg_ls_waldir();

-- 3. How much disk is free?
-- (Run on the OS, not in psql)
-- df -h /var/lib/postgresql
```

### 5.2 Investigate a Lagging Slot

```sql
-- How fast is the consumer falling behind?
-- Run twice, 60 seconds apart

-- Run 1
SELECT slot_name, confirmed_flush_lsn AS lsn_t1
FROM pg_replication_slots WHERE slot_name = 'my_cdc_slot';

-- Wait 60 seconds ...

-- Run 2 – compare LSN difference to measure lag growth rate
SELECT
  slot_name,
  pg_size_pretty(
    pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)
  ) AS current_lag,
  active,
  active_pid
FROM pg_replication_slots WHERE slot_name = 'my_cdc_slot';
```

### 5.3 Emergency: Drop a Dead Slot

```sql
-- ⚠️ WARNING: Dropping a slot means the consumer loses its position.
-- It must re-sync from the beginning or a known snapshot.
-- Only do this if the consumer is confirmed dead and disk is at risk.

-- List slots and their WAL retention
SELECT slot_name,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal,
  active
FROM pg_replication_slots;

-- Drop the slot
SELECT pg_drop_replication_slot('my_dead_slot');

-- Verify WAL directory shrinks after the next checkpoint
CHECKPOINT;
SELECT pg_size_pretty(sum(size)) FROM pg_ls_waldir();
```

### 5.4 Force a Checkpoint to Reclaim Disk

```sql
-- After dropping a slot, force checkpoint to reclaim WAL files
CHECKPOINT;

-- Then verify
SELECT pg_size_pretty(sum(size)) FROM pg_ls_waldir();
```

---

## 6. Automating WAL Lag Monitoring

### 6.1 Shell Script (run via cron every 5 minutes)

```bash
#!/bin/bash
# /usr/local/bin/check_wal_lag.sh
# Runs as postgres user; alerts via SNS if slot lag > threshold

THRESHOLD_BYTES=$((5 * 1024 * 1024 * 1024))  # 5 GB
SNS_TOPIC_ARN="arn:aws:sns:eu-west-2:ACCOUNT_ID:db-alerts"
REGION="eu-west-2"

# Query PostgreSQL for slot lag in bytes
psql -U postgres -At -c "
  SELECT slot_name,
    pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS lag_bytes
  FROM pg_replication_slots;
" | while IFS='|' read -r slot lag_bytes; do
  slot=$(echo "$slot" | xargs)
  lag_bytes=$(echo "$lag_bytes" | xargs)

  if [ "$lag_bytes" -gt "$THRESHOLD_BYTES" ]; then
    lag_gb=$(echo "scale=2; $lag_bytes / 1073741824" | bc)
    aws sns publish \
      --topic-arn "$SNS_TOPIC_ARN" \
      --region "$REGION" \
      --subject "⚠️ WAL Slot Lag Alert: $slot" \
      --message "Replication slot '$slot' has accumulated ${lag_gb} GB of WAL.
Consumer may be stopped or too slow.
Server: $(hostname)
Time: $(date -u)
Action required: Check consumer health or drop slot if dead."
  fi
done
```

```bash
# Add to cron (runs every 5 minutes as postgres user)
# sudo crontab -u postgres -e
*/5 * * * * /usr/local/bin/check_wal_lag.sh >> /var/log/wal-lag-check.log 2>&1
```

### 6.2 CloudWatch Custom Metric (push WAL lag to CloudWatch)

```bash
#!/bin/bash
# Push WAL slot lag as a custom CloudWatch metric

REGION="eu-west-2"
NAMESPACE="PostgreSQL/WAL"
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

psql -U postgres -At -c "
  SELECT slot_name,
    pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS lag_bytes
  FROM pg_replication_slots;
" | while IFS='|' read -r slot lag_bytes; do
  slot=$(echo "$slot" | xargs)
  lag_bytes=$(echo "$lag_bytes" | xargs)

  aws cloudwatch put-metric-data \
    --region "$REGION" \
    --namespace "$NAMESPACE" \
    --metric-name "SlotLagBytes" \
    --dimensions "SlotName=$slot,InstanceId=$INSTANCE_ID" \
    --value "$lag_bytes" \
    --unit Bytes
done
```

---

## 7. pg_stat_replication – Monitor Active Streaming Consumers

```sql
-- For active streaming consumers (not polling via SQL)
SELECT
  application_name,
  client_addr,
  state,
  sent_lsn,
  write_lsn,
  flush_lsn,
  replay_lsn,
  pg_size_pretty(
    pg_wal_lsn_diff(sent_lsn, replay_lsn)
  ) AS replay_lag,
  write_lag,
  flush_lag,
  replay_lag AS replay_lag_time
FROM pg_stat_replication;
```

---

## 8. WAL Growth Quick Diagnostics – Decision Tree

```
Is disk usage > 70%?
├── YES → Emergency
│   ├── Are there inactive slots?
│   │   ├── YES → Drop dead slots → CHECKPOINT
│   │   └── NO  → Expand EBS volume immediately
│   └── After resolving: review max_slot_wal_keep_size
│
└── NO → Routine monitoring
    ├── Is any slot lag > 2 GB?
    │   ├── YES → Is consumer running?
    │   │   ├── NO  → Restart consumer process
    │   │   └── YES → Consumer is slow; scale up consumer or reduce write load
    │   └── NO  → System healthy ✅
    └── Is max_slot_wal_keep_size set?
        ├── YES → Good ✅
        └── NO  → Set it now to prevent disk-full crashes
```

---

## 9. Summary Checklist

| Action                                         | Frequency   | Command / Location                              |
|------------------------------------------------|-------------|------------------------------------------------|
| Check slot lag sizes                           | Every 5 min | `pg_replication_slots` query                   |
| Check WAL directory total size                 | Every 5 min | `pg_ls_waldir()`                               |
| Check disk free space                          | Every 1 min | CloudWatch `disk_used_percent`                 |
| Verify consumers are active (`active = true`)  | Every 5 min | `pg_replication_slots.active`                  |
| Review `max_slot_wal_keep_size` is set         | One-time    | `postgresql.conf`                              |
| Alert: slot lag > 2 GB                         | Automated   | Script / CloudWatch custom metric              |
| Alert: disk > 70% used                         | Automated   | CloudWatch alarm                               |
| Drop dead slots                                | On-demand   | `pg_drop_replication_slot()`                   |
| Monthly: review WAL write rate vs disk budget  | Monthly     | Measure LSN delta over peak period             |

