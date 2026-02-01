There is no single “best” MySQL config, but there is a battle-tested baseline that is well-optimized for:

MySQL 8.x

Ubuntu 24.04

EC2 (ARM / Graviton)

InnoDB-only workloads (typical)

Below is a production-grade optimized my.cnf, followed by why each setting matters and how to size it correctly.

## ✅ Recommended Optimized MySQL 8.x Configuration

```ini
[mysqld]

################################################################################
# BASICS & SECURITY
################################################################################

# Run MySQL as this system user. user mysql is default if not specified.
# Test: ps -ef | grep mysqld
user=mysql

# Skip DNS lookups for connecting hosts (improves connection speed)
# Security: Prevents DNS-based attacks
# Performance: Faster connections (no DNS resolution delay)
# Use IP addresses in GRANT statements when this is enabled
skip-name-resolve

# Disable LOAD DATA LOCAL INFILE (security hardening)
# Prevents local file system access via SQL injection
# Keep disabled unless you specifically need this feature
local-infile=0

# ===============================================
# MySQL 8 SQL Mode – Strict Error Handling & Data Integrity
# ===============================================
# ONLY_FULL_GROUP_BY        : Prevents ambiguous queries using GROUP BY; ensures deterministic results
# STRICT_TRANS_TABLES       : Rejects invalid or truncated data instead of silently adjusting
# NO_ZERO_IN_DATE           : Prevents invalid dates like '2026-00-15'
# NO_ZERO_DATE              : Prevents completely zero dates like '0000-00-00'
# ERROR_FOR_DIVISION_BY_ZERO: Raises an error on division by zero instead of returning NULL
# NO_ENGINE_SUBSTITUTION    : Prevents silent substitution of storage engines if the requested engine is unavailable
# ===============================================
sql_mode=ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION

################################################################################
# CONNECTION HANDLING
################################################################################

# Maximum simultaneous client connections
# Rule: Set based on your app's connection pool size
# Too high: Wastes memory (each connection uses ~256KB-1MB)
# Too low: Connection errors during traffic spikes
# For most apps: 100-300 is sufficient (use connection pooling!)
max_connections=200

# ===============================================
# Prevent Host Blocking After Failed Connection Attempts
# ===============================================
# max_connect_errors : Number of consecutive failed connection attempts
# from a host before MySQL blocks further connections from it.
# Default is 100 (very low), which can cause accidental lockouts
# during deployments or automated scripts.
# Setting this high (100000) reduces the risk of accidental blocks,
# while still allowing legitimate hosts to reconnect normally.
max_connect_errors=100000

# Seconds before closing inactive non-interactive connections
# Interactive = mysql CLI, Non-interactive = app connections
# 600s (10 min) is reasonable for most apps with connection pooling
# Too low: Frequent reconnections (overhead)
# Too high: Idle connections waste resources
wait_timeout=600
interactive_timeout=600

# ===============================================
# Thread Cache Size – Reduce Thread Creation Overhead
# ===============================================
# thread_cache_size : Number of threads MySQL keeps in cache for reuse.
# When a client disconnects, the thread is put into this cache.
# Reusing threads avoids the overhead of creating new threads for
# each connection, improving performance under high connection churn.
#
# Recommended: roughly 10–50% of max_connections, or roughly equal to
# the number of connections you expect to cycle frequently.
# Example: for max_connections=200, a thread_cache_size of 100 is ideal.
thread_cache_size=100

################################################################################
# InnoDB CORE SETTINGS (⚠️ MOST IMPORTANT FOR PERFORMANCE)
################################################################################

# Use InnoDB as default storage engine (ACID-compliant, transactional)
# InnoDB is the only production-grade engine in MySQL 8
default_storage_engine=InnoDB

# ===============================================
# InnoDB – Default Storage Engine and Buffer Pool
# ===============================================
# Use InnoDB as default storage engine (ACID-compliant, transactional)
# InnoDB is the only production-grade engine in MySQL 8
default_storage_engine=InnoDB

# InnoDB buffer pool size (THE MOST CRITICAL SETTING)
# Purpose: Caches table data and indexes in memory for high performance.
# Rules of thumb:
#   - Dedicated DB server: 70-75% of total RAM
#   - Shared server (with app): 50-60% of total RAM
# Examples:
#   - 4 GB RAM (t4g.medium): innodb_buffer_pool_size=3G
#   - 8 GB RAM (t4g.large):  innodb_buffer_pool_size=6G
#   - 16 GB RAM (r7g.large): innodb_buffer_pool_size=12G
# ⚠️ Allocate as much as possible (up to 70-75% of RAM) for best performance.
# Adjust based on instance RAM and workload (especially for read-heavy workloads).
innodb_buffer_pool_size=3G

# ===============================================
# InnoDB Buffer Pool Instances – Improve Concurrency
# ===============================================
# innodb_buffer_pool_instances : Number of separate memory instances for the buffer pool.
# Purpose: Reduces internal locking contention and improves concurrency
# when multiple threads access the buffer pool.
#
# Rule of thumb:
#   - 1 instance per GB of buffer pool (up to 8–16)
#   - For buffer pool >= 4GB: use 4–8 instances
#   - For buffer pool < 4GB: use 1–4 instances
#
# Example: For a 3G buffer pool (t4g.medium), 4 instances is reasonable
innodb_buffer_pool_instances=4


# ===============================================
# InnoDB Redo Log File Size – Transaction Logging
# ===============================================
# innodb_log_file_size : Size of each InnoDB redo (transaction) log file.
# Purpose: Write-ahead logging for crash recovery and durability.
#
# Sizing guidance:
#   - Larger log files → Better write performance, fewer checkpoints,
#     but slower crash recovery.
#   - Smaller log files → Faster recovery, more frequent checkpoints,
#     which can slow down write-heavy workloads.
#
# Recommended total redo log space: 1G – 4G
# Modern MySQL 8.x: 1G–2G per file is safe and performant.
innodb_log_file_size=1G

# ===============================================
# InnoDB Log Buffer Size – Memory for Redo Log Writes
# ===============================================
# innodb_log_buffer_size : Memory allocated to store redo log entries before
# flushing them to disk.
#
# Sizing guidance:
#   - Larger buffer → Fewer disk writes, better performance for write-heavy workloads
#   - Smaller buffer → More frequent flushes, which can slow down writes
#
# Default is 16M, which is often too small for modern workloads.
# Recommended: 64M–256M depending on transaction volume.
innodb_log_buffer_size=64M
# ===============================================
# InnoDB I/O and Flush Settings – Optimize Disk Performance
# ===============================================

# Flush method – how MySQL writes data to disk
# O_DIRECT: Bypasses OS cache to prevent double buffering
# Recommended for dedicated DB servers for consistent performance
# Alternatives:
#   - fsync: Uses OS cache (slower, double buffering)
#   - O_DSYNC: Direct I/O for logs only
innodb_flush_method=O_DIRECT

# Durability vs. performance: log flushing on transaction commit
# 1 = Flush log to disk on every commit (ACID-safe, slowest, safest)
# 2 = Flush logs every second (~1 sec potential data loss, faster)
# 0 = Flush every second without OS write (risky, not recommended)
# ⚠️ Keep at 1 for production unless temporary data loss is acceptable
innodb_flush_log_at_trx_commit=1

# Store each InnoDB table in its own .ibd file
# Benefits: easier backups, reclaim space on DROP TABLE, better I/O
# Default in MySQL 8.x – keep enabled for clarity
innodb_file_per_table=1

# I/O capacity for background tasks (flushes, checkpoints)
# Based on disk type and IOPS capability:
#   - HDD: ~200
#   - SSD gp2: ~3000
#   - SSD gp3: baseline 12000, max 16000
#   - NVMe: 10000+
# For EC2 gp3 volumes: 2000–4000 is reasonable for good performance
innodb_io_capacity=2000
innodb_io_capacity_max=4000

# Number of I/O threads for read and write operations
# Default: 4 each
# For SSD: 4–8 each is good
# High-performance workloads: 8–16 each
# ARM/Graviton instances: 4 is sufficient unless heavy I/O
innodb_read_io_threads=4
innodb_write_io_threads=4

################################################################################
# TEMPORARY TABLES & MEMORY
################################################################################

# Maximum size for in-memory temporary tables
# When exceeded, temp table is written to disk (slower)
# Used for: GROUP BY, ORDER BY, DISTINCT, UNION
# 64M-256M is reasonable for most apps
# Too high: Wastes memory
# Too low: Frequent disk writes for temp tables
tmp_table_size=64M
max_heap_table_size=64M  # Must match tmp_table_size

# Internal temporary table storage engine
# TempTable: New in MySQL 8, faster than MEMORY engine
# Keep this setting (default in MySQL 8.0.16+)
internal_tmp_mem_storage_engine=TempTable

################################################################################
# QUERY CACHE (MySQL 8.0: REMOVED/DISABLED)
################################################################################

# Query cache was removed in MySQL 8.0 (caused more harm than good)
# These settings have no effect in MySQL 8.0+
# Kept for backward compatibility if downgrading
query_cache_type=0
query_cache_size=0

################################################################################
# LOGGING (MONITORING & DEBUGGING)
################################################################################

# Error log location (startup issues, crashes, warnings)
# Always enabled, check this file for problems
log_error=/var/lib/mysql/error.log

# Slow query log (identify performance bottlenecks)
# Enable: 1, Disable: 0
# Essential for production monitoring and optimization
slow_query_log=1
slow_query_log_file=/var/lib/mysql/slow-query.log

# Queries taking longer than this are logged (in seconds)
# 1 second is a good starting point
# For high-performance apps: 0.5 or 0.1
# For reporting/analytics: 5-10
long_query_time=1

# Log queries that don't use indexes (useful during development)
# 0 = Don't log (recommended for production - too noisy)
# 1 = Log (useful for dev/staging to find missing indexes)
log_queries_not_using_indexes=0

################################################################################
# BINARY LOGGING (BACKUPS & POINT-IN-TIME RECOVERY)
################################################################################

# Enable binary logging for backups and replication
# Required for: mysqldump with --single-transaction, point-in-time recovery
# Stores all data-modifying queries (INSERT, UPDATE, DELETE)
log-bin=mysql-bin

# Binary log format
# ROW: Logs actual row changes (safest, recommended)
#   - Pros: Safest for replication, no ambiguity
#   - Cons: Larger log files
# STATEMENT: Logs SQL statements (smaller logs, replication issues)
# MIXED: Automatic switching (not recommended)
binlog_format=ROW

# Binary log retention period (in seconds)
# Old value: 604800 (7 days) - TOO LONG when you have hourly backups
# New value: 172800 (2 days) - Sufficient for point-in-time recovery
# Why 2 days is enough:
#   - You have hourly mysqldump backups to S3
#   - You have daily EBS snapshots
#   - Binary logs only needed for recovery between backup intervals
#   - Saves disk space (binary logs can grow large)
# Formula: retention >= (backup_interval × 2)
#   - Hourly backups → 2-4 hours of binlogs sufficient
#   - Daily backups → 48 hours (2 days) is safe
binlog_expire_logs_seconds=172800  # 2 days (recommended with frequent backups)

# Sync binary log to disk after every N commits
# 1 = Sync on every commit (safest, no binlog data loss)
#   - Best for production (ACID compliance)
# 100 = Sync every 100 commits (faster, small data loss risk)
# 0 = Let OS decide (fastest, higher data loss risk)
# ⚠️ Keep at 1 for production unless you accept binlog data loss
sync_binlog=1

# Maximum size of a single binary log file before rotation
# When reached, MySQL creates a new binlog file
# 100M is good (rotates frequently, easier to manage)
# Too large: Hard to transfer/backup individual files
# Too small: Too many files, overhead
max_binlog_size=100M

################################################################################
# CHARACTER SET & COLLATION
################################################################################

# Default character set for all databases and tables
# utf8mb4: Full UTF-8 support (including emojis, 4-byte characters)
# utf8: Legacy, only supports 3-byte UTF-8 (don't use)
# ⚠️ Always use utf8mb4 for new applications
character-set-server=utf8mb4

# Default collation (sorting/comparison rules)
# utf8mb4_unicode_ci: Better sorting for international characters
# utf8mb4_general_ci: Faster, but less accurate for non-English
# utf8mb4_0900_ai_ci: MySQL 8.0 default (even better, accent-insensitive)
# Recommended: utf8mb4_unicode_ci (widely compatible)
collation-server=utf8mb4_unicode_ci

################################################################################
# NETWORKING
################################################################################

# IP address to bind to
# 0.0.0.0: Listen on all interfaces (allows remote connections)
# 127.0.0.1: Listen only on localhost (local connections only)
# For Docker/EC2: Use 0.0.0.0, control access via firewall/security groups
bind-address=0.0.0.0

# Disable internal host cache (related to skip-name-resolve)
# Prevents issues with cached DNS lookups
# Recommended when skip-name-resolve is enabled
skip-host-cache

################################################################################
# OPTIONAL: PRODUCTION HARDENING
################################################################################

# Enable performance schema for monitoring (small overhead)
# Provides detailed performance metrics and query statistics
# Useful for troubleshooting and optimization
# Disable only if you need maximum performance (not recommended)
# performance_schema=ON

# Prevent creation of symbolic links (security)
# Disables DATA DIRECTORY and INDEX DIRECTORY options
# Prevents symlink-based privilege escalation
# skip-symbolic-links

# Restrict LOAD DATA INFILE and SELECT INTO OUTFILE to this directory
# Prevents reading/writing arbitrary files on the server
# secure-file-priv=/var/lib/mysql-files
```

## 🔧 How to Size the Critical Values (Very Important)

### 1️⃣ innodb_buffer_pool_size (THE MOST CRITICAL SETTING)

**Purpose:** Caches table data and indexes in RAM - the single most important performance setting.

**Rule of thumb:**
- **Dedicated DB server** → 70–75% of RAM
- **Shared server** (app + DB on same instance) → 50–60% of RAM

**Examples:**

| Instance Type | RAM | Recommended Buffer Pool | Setting |
|---------------|-----|------------------------|---------|
| t4g.micro | 1 GB | 512 MB - 768 MB | `innodb_buffer_pool_size=512M` |
| t4g.small | 2 GB | 1.2 GB - 1.5 GB | `innodb_buffer_pool_size=1536M` |
| t4g.medium | 4 GB | 2.5 GB - 3 GB | `innodb_buffer_pool_size=3G` |
| t4g.large | 8 GB | 5.5 GB - 6 GB | `innodb_buffer_pool_size=6G` |
| m7g.large | 8 GB | 6 GB | `innodb_buffer_pool_size=6G` |
| r7g.large | 16 GB | 12 GB | `innodb_buffer_pool_size=12G` |
| r7g.xlarge | 32 GB | 24 GB | `innodb_buffer_pool_size=24G` |

**Why it matters:**
- Data in buffer pool = read from RAM (microseconds)
- Data not in buffer pool = read from disk (milliseconds)
- **1000x performance difference!**

**How to check if it's large enough:**
```sql
-- Check buffer pool hit ratio (should be > 99%)
SHOW STATUS LIKE 'Innodb_buffer_pool_read%';
```

---

### 2️⃣ innodb_log_file_size (Write Performance)

**Purpose:** Controls redo log size for crash recovery and write performance.

**Impact:**
- **Too small** → Frequent checkpoints → Slow writes → High I/O
- **Too large** → Slower crash recovery (but modern MySQL recovers fast)

**Recommended:**
- Total redo log size = **1–4 GB**
- Single file size = **1G** (most common)
- With `innodb_log_files_in_group=2` (default), total = 2GB

**Configuration:**
```ini
innodb_log_file_size=1G
# Total redo log space = 1G × 2 (default files) = 2GB
```

**For heavy write workloads:**
```ini
innodb_log_file_size=2G
# Total = 4GB (excellent for write-heavy apps)
```

---

### 3️⃣ max_connections (Don't Overshoot!)

**Purpose:** Maximum simultaneous client connections.

**❌ Bad (common mistake):**
```ini
max_connections=1000  # Wastes ~1GB RAM for idle connections!
```

**✅ Good:**
```ini
max_connections=100-300  # Sufficient for most apps
```

**Why limit this?**
- Each connection uses **256KB - 1MB** of RAM
- 1000 connections = **~1GB RAM wasted** on connection buffers
- Most apps use **connection pooling** (e.g., 10-50 connections max)

**How to size:**
```
max_connections = (number of app servers × connection pool size) + safety margin

Example:
  - 3 app servers
  - Each has connection pool of 20
  - Safety margin: 50
  
max_connections = (3 × 20) + 50 = 110 → Set to 150
```

**If you need more:**
→ Use connection pooling (PgBouncer, ProxySQL), **NOT** more MySQL threads.

---

### 4️⃣ binlog_expire_logs_seconds (Binary Log Retention)

**Purpose:** How long to keep binary logs before auto-deletion.

**Default:** 604800 seconds (7 days) - Often too long!

**Recommended with frequent backups:**
```ini
binlog_expire_logs_seconds=172800  # 2 days
```

**Why 2 days is enough:**

Given your backup strategy:
- ✅ **Hourly mysqldump backups** to S3
- ✅ **Daily EBS snapshots**

**Recovery scenarios:**

| Disaster | Recovery Method | Binary Logs Needed? |
|----------|----------------|---------------------|
| Dropped table (2 hours ago) | Restore from S3 backup (1 hour old) + replay 1 hour of binlogs | ✅ 1 hour |
| Database corruption (yesterday) | Restore from EBS snapshot (yesterday) + replay today's binlogs | ✅ 24 hours |
| Complete data center failure | Restore from S3 (hourly) + replay last hour of binlogs | ✅ 1 hour |

**Formula:**
```
Retention = (Longest backup interval × 2) + Safety margin

Your case:
  - Longest backup interval: 1 day (EBS snapshots)
  - Formula: 1 day × 2 = 2 days
  
binlog_expire_logs_seconds = 172800 (2 days)
```

**Benefits of shorter retention:**
- ✅ **Saves disk space** (binlogs can grow to 10-100GB+)
- ✅ **Faster binlog rotation** (cleaner file management)
- ✅ **Still safe** with hourly backups

**When to use longer retention:**
- Delayed replication (7-30 days)
- Compliance requirements (30+ days)
- No frequent backups (backup once per week)

**Current disk usage check:**
```bash
# On MySQL instance
docker exec mysql-server du -sh /var/lib/mysql/mysql-bin.*
```

---

## 📚 How Binary Logs Are Used (Point-in-Time Recovery)

### What Are Binary Logs?

Binary logs record **all data-modifying operations** (INSERT, UPDATE, DELETE, CREATE, DROP, etc.) in the order they occurred.

**Purpose:**
1. **Point-in-time recovery** - Restore to exact moment before disaster
2. **Replication** - Replicate data to standby servers
3. **Auditing** - Track all database changes

---

### Recovery Scenario Example

**Disaster:** Developer accidentally ran `DROP TABLE users;` at **14:30 today**.

**Your backups:**
- Hourly S3 backups: Last at **14:00** (before disaster)
- Daily EBS snapshot: Yesterday at **03:00**
- Binary logs: Last 2 days

**Recovery steps:**

#### Step 1: Restore from S3 backup (14:00)
```bash
# Download backup
aws s3 cp s3://bucket/mysql-backups/staging/myapp/2026-01-20-mydb/140000.sql.gz .

# Restore to MySQL
gunzip 140000.sql.gz
docker exec -i mysql-server mysql -u root -p < 140000.sql
```

**Status:** Database restored to 14:00, but missing 30 minutes of data (14:00 - 14:30)

---

#### Step 2: Replay binary logs from 14:00 to 14:29 (before DROP TABLE)

```bash
# On MySQL instance
docker exec -it mysql-server bash

# Find binary log position at 14:00
mysqlbinlog mysql-bin.000123 --start-datetime="2026-01-20 14:00:00" \
  --stop-datetime="2026-01-20 14:29:59" > recovery.sql

# Review the recovery file (make sure it stops BEFORE DROP TABLE)
grep -n "DROP TABLE" recovery.sql  # Should show the DROP at 14:30
sed -n '1,12345p' recovery.sql > safe_recovery.sql  # Stop before DROP line

# Replay safe transactions
mysql -u root -p < safe_recovery.sql
```

**Result:** ✅ Database fully recovered to 14:29:59 (1 second before disaster)

---

### Why 2 Days of Binary Logs is Enough

| Backup Type | Frequency | Max Data Loss | Binary Logs Needed |
|-------------|-----------|---------------|-------------------|
| **S3 mysqldump** | Hourly | 1 hour | **1-2 hours** |
| **EBS snapshot** | Daily | 24 hours | **24 hours** |
| **Combined** | Both | 1 hour (S3 restore) | **2 hours max** |

**With 2-day retention (172800 seconds):**
- ✅ Recover from any hourly backup failure (48 backups worth)
- ✅ Replay up to 48 hours of transactions
- ✅ Cover weekend incidents discovered Monday
- ✅ Plenty of margin for delayed discovery

**Disk space savings:**
```
7 days of binlogs: ~14-70 GB (depending on write volume)
2 days of binlogs: ~4-20 GB
Savings: 10-50 GB of disk space
```

---

### Binary Log Commands

**View current binary logs:**
```sql
SHOW BINARY LOGS;
```

**View current position:**
```sql
SHOW MASTER STATUS;
```

**Manually purge old binlogs:**
```sql
-- Purge logs older than 2 days
PURGE BINARY LOGS BEFORE DATE_SUB(NOW(), INTERVAL 2 DAY);

-- Purge logs before specific file
PURGE BINARY LOGS TO 'mysql-bin.000123';
```

**View binlog contents:**
```bash
# Human-readable format
mysqlbinlog mysql-bin.000123

# Filter by time
mysqlbinlog mysql-bin.000123 \
  --start-datetime="2026-01-20 14:00:00" \
  --stop-datetime="2026-01-20 15:00:00"
```

---

## ## ⚠️ Important Things You Should NOT Tune (Common Mistakes)

### ❌ key_buffer_size
**Why:** This is for **MyISAM** storage engine only (deprecated)
- InnoDB doesn't use this setting
- Wasted memory if you set it high
- Default is fine (skip this entirely)

**Wrong:**
```ini
key_buffer_size=2G  # Wastes 2GB of RAM!
```

**Right:**
```ini
# Don't set it at all (InnoDB uses innodb_buffer_pool_size)
```

---

### ❌ Query Cache
**Why:** Removed in MySQL 8.0 (caused more harm than good)
- Created lock contention on busy servers
- Cache invalidation issues
- Modern apps use application-level caching (Redis, Memcached)

**These do nothing in MySQL 8:**
```ini
query_cache_type=1
query_cache_size=256M
```

**Right:**
```ini
# Already disabled by default in MySQL 8
# Or explicitly disable:
query_cache_type=0
query_cache_size=0
```

---

### ❌ Massive Per-Thread Buffers
**Why:** Each connection gets these buffers, multiplies by max_connections

**Dangerous settings:**
```ini
sort_buffer_size=32M        # Default: 256K
read_buffer_size=16M        # Default: 128K
read_rnd_buffer_size=16M    # Default: 256K
join_buffer_size=16M        # Default: 256K

# With max_connections=200:
# Total memory waste: 200 × (32M + 16M + 16M + 16M) = 16 GB!
```

**Right approach:**
```ini
# Use defaults (256K-512K each)
# MySQL allocates these only when needed
# Rarely need to increase
```

**When to increase:**
- `sort_buffer_size`: Large `ORDER BY` without indexes (fix index instead!)
- `join_buffer_size`: Large joins without indexes (fix query instead!)

---

### ❌ Blind Copy-Paste Configs
**Why:** Every workload is different

**Bad sources:**
- Blog posts from 2010 (outdated)
- MySQL 5.x configs (different defaults)
- Configs for 512GB servers (wrong scale)
- "Optimized" configs without explanations

**Right approach:**
1. Start with **this guide's baseline**
2. **Monitor** with slow query log
3. **Adjust** only what metrics show is needed
4. **Measure** the impact

---

### ❌ Premature "Optimization"
**Common mistake:** Tuning everything before understanding the workload

**Wrong order:**
1. ~~Set 50 MySQL variables~~
2. ~~Deploy application~~
3. ~~Wonder why it's slow~~

**Right order:**
1. ✅ Deploy with **baseline config** (this guide)
2. ✅ Monitor with **slow query log**
3. ✅ Identify actual bottlenecks
4. ✅ Add missing **indexes** (99% of problems)
5. ✅ Optimize **queries** (not MySQL settings)
6. ✅ Adjust settings **only if needed**

---

### ❌ Ignoring Indexes
**Why:** No amount of MySQL tuning fixes missing indexes

**Example slow query:**
```sql
-- 5 seconds on 1 million rows
SELECT * FROM users WHERE email = 'user@example.com';
```

**Wrong fix:**
```ini
# Increase buffer pool!
innodb_buffer_pool_size=32G  # ❌ Doesn't help
```

**Right fix:**
```sql
-- Add index (query now takes 0.001 seconds)
CREATE INDEX idx_users_email ON users(email);  # ✅ 5000x faster
```

**Rule:** Index first, tune second.

🧠 ARM (Graviton)–Specific Notes

No special MySQL flags needed

InnoDB performs very well on ARM

I/O settings (io_capacity) matter more than CPU tuning

🔒 Production Hardening (Optional but Recommended)
performance_schema=ON
skip-symbolic-links
secure-file-priv=/var/lib/mysql-files

✅ Final Recommendation

For your EC2 MySQL (ARM / Ubuntu 24):

Focus on:

innodb_buffer_pool_size

innodb_log_file_size

Reasonable max_connections

Avoid “tuning everything”

Measure with slow query log first---
## 🧠 ARM (Graviton) – Enhanced Notes
### Good News: MySQL Works Great on ARM
**No special configuration needed!** MySQL 8.x is fully optimized for ARM64 architecture.
### What Works Well on Graviton
✅ **InnoDB storage engine** - Excellent performance  
✅ **Buffer pool operations** - Same as x86  
✅ **Query execution** - Often 10-20% faster than x86  
✅ **Compression** - Native ARM instructions  
### Graviton vs Intel Performance
| Workload Type | Graviton Performance | Notes |
|---------------|---------------------|--------|
| **Read-heavy** | 15-25% faster | Better cache efficiency |
| **Write-heavy** | 10-20% faster | Efficient I/O operations |
| **Mixed** | 10-15% faster | Overall good performance |
| **Cost** | 20% cheaper | Same performance, lower price |
**Bottom line:** Use the same configuration as x86, enjoy better performance and lower costs.
---
## 📊 Quick Reference Card
```
┌────────────────────────────────────────────────────────────┐
│ MYSQL 8.x CONFIGURATION QUICK REFERENCE                    │
├────────────────────────────────────────────────────────────┤
│                                                            │
│ ⚠️  MOST CRITICAL (MUST SET):                             │
│   • innodb_buffer_pool_size = 70% of RAM                  │
│   • innodb_log_file_size = 1G                             │
│   • max_connections = 100-300                             │
│   • binlog_expire_logs_seconds = 172800 (2 days)          │
│                                                            │
│ ✅ IMPORTANT (PRODUCTION):                                 │
│   • innodb_flush_log_at_trx_commit = 1 (ACID)            │
│   • sync_binlog = 1 (no binlog data loss)                │
│   • innodb_flush_method = O_DIRECT (no double buffer)    │
│   • slow_query_log = 1 (monitoring)                       │
│                                                            │
│ 🎯 PERFORMANCE (TUNE TO WORKLOAD):                        │
│   • innodb_io_capacity = 2000-4000 (match EBS IOPS)      │
│   • innodb_buffer_pool_instances = 4-8                    │
│   • tmp_table_size = 64M-256M                             │
│                                                            │
│ ❌ AVOID (COMMON MISTAKES):                                │
│   • key_buffer_size (MyISAM only)                         │
│   • query_cache_* (removed in MySQL 8)                    │
│   • Massive per-thread buffers                            │
│   • max_connections > 500 (use pooling!)                  │
│                                                            │
│ 📏 SIZING GUIDE:                                           │
│   • t4g.micro (1GB):  innodb_buffer_pool_size=512M        │
│   • t4g.small (2GB):  innodb_buffer_pool_size=1536M       │
│   • t4g.medium (4GB): innodb_buffer_pool_size=3G          │
│   • t4g.large (8GB):  innodb_buffer_pool_size=6G          │
│   • r7g.large (16GB): innodb_buffer_pool_size=12G         │
│                                                            │
└────────────────────────────────────────────────────────────┘
```
---
**Last Updated:** January 2026  
**MySQL Version:** 8.0+  
**Platform:** Ubuntu 24.04 / ARM (Graviton) / EC2 / Docker
