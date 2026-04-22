# PostgreSQL → PostgreSQL Logical Replication (Publisher / Subscriber)

---

## 1. How It Works — Is It the Same as CDC?

Yes — PostgreSQL-to-PostgreSQL replication uses the **same logical WAL infrastructure** as CDC.
The difference is in who reads the WAL and what they do with it.

| Aspect | CDC (wal2json / pg_recvlogical) | PgSQL → PgSQL Subscription |
|---|---|---|
| WAL level required | `logical` | `logical` |
| Replication slot | ✅ Yes (logical slot) | ✅ Yes (logical slot, auto-created) |
| Output plugin | `wal2json`, `test_decoding` | `pgoutput` (built-in, native) |
| Publication required | ❌ Optional (wal2json reads raw WAL) | ✅ Required |
| Who applies changes | Your consumer (Airbyte, custom) | PostgreSQL itself on the subscriber |
| Schema sync | Manual | Manual (schema is NOT auto-synced) |
| Data copy on setup | Manual | Automatic by default (`copy_data = true`) |

> **Key point:** Both use the same `wal_level = logical` and the same replication slot mechanism.
> The subscriber just uses the native `pgoutput` plugin and applies changes automatically
> as SQL on the target database — you do not need `wal2json` installed for this.

---

## 2. Architecture Overview

```
┌─────────────────────────────────┐        ┌─────────────────────────────────┐
│         PUBLISHER               │        │         SUBSCRIBER              │
│  (Source PostgreSQL instance)   │        │  (Target PostgreSQL instance)   │
│                                 │        │                                 │
│  WAL (wal_level = logical)      │        │  Applies changes as SQL         │
│         │                       │        │  INSERT / UPDATE / DELETE       │
│         ▼                       │        │         ▲                       │
│  Logical Replication Slot       │──WAL──▶│  Subscription (rocksub)        │
│  (pgoutput plugin)              │  stream│                                 │
│         ▲                       │        │  Connects to publisher slot     │
│         │                       │        │  and continuously streams WAL   │
│  Publication (rockpub)          │        │                                 │
│  FOR ALL TABLES                 │        │  Tables must already exist      │
│                                 │        │  (schema copied separately)     │
└─────────────────────────────────┘        └─────────────────────────────────┘
```

---

## 3. Prerequisites on the Publisher

Same as CDC setup — these must be configured before creating any subscription.

### 3.1 postgresql.conf

```conf
wal_level = logical
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = 1GB
max_slot_wal_keep_size = 16GB
```

> ⚠️ Restart required after changing `wal_level`.

### 3.2 pg_hba.conf

Allow the subscriber to connect for replication:

```conf
# Allow subscriber IP to connect for replication
host    replication     replication_user    <subscriber_ip>/32    scram-sha-256

# Also allow normal connection to read the database
host    your_db         replication_user    <subscriber_ip>/32    scram-sha-256
```

Reload after editing:

```bash
sudo systemctl reload postgresql
```

### 3.3 Replication User on Publisher

```sql
-- Create a dedicated replication user on the PUBLISHER
CREATE ROLE replication_user
WITH LOGIN REPLICATION PASSWORD 'strong_password';

GRANT CONNECT ON DATABASE your_db TO replication_user;
GRANT USAGE ON SCHEMA public TO replication_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO replication_user;

-- Future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO replication_user;
```

---

## 4. Step-by-Step Setup

### Step 1 — Create the Publication on the Publisher

```sql
-- Connect to the source database on the PUBLISHER
\c your_db

-- Option A: Replicate ALL tables (including future tables)
CREATE PUBLICATION rockpub FOR ALL TABLES;

-- Option B: Replicate specific tables only
CREATE PUBLICATION rockpub FOR TABLE scott.employee, scott.departments;

-- Verify
SELECT pubname, puballtables, pubinsert, pubupdate, pubdelete
FROM pg_publication;
```

---

### Step 2 — Copy the Schema to the Subscriber

> ⚠️ PostgreSQL logical replication does **NOT** sync schema automatically.
> Tables must already exist on the subscriber before the subscription starts.
> If tables are missing, the subscription will error on first apply.

```bash
# Run this from any machine that can reach both servers
# Dumps schema only (-s = schema only, -Fc = custom format)
pg_dump \
  -h <publisher_ip> \
  -p 5432 \
  -d your_db \
  -U postgres \
  -Fc \
  --schema-only \
  | pg_restore \
      -h <subscriber_ip> \
      -p 5432 \
      -d your_db \
      -U postgres
```

> If the target database does not exist yet on the subscriber, create it first:
> ```sql
> CREATE DATABASE your_db;
> ```

---

### Step 3 — Create the Subscription on the Subscriber

```sql
-- Connect to the target database on the SUBSCRIBER
\c your_db

-- Option A: With initial data copy (default)
-- PostgreSQL will copy all existing rows from the publisher first,
-- then stream ongoing changes
CREATE SUBSCRIPTION rocksub
  CONNECTION 'host=<publisher_ip> dbname=your_db user=replication_user password=strong_password port=5432'
  PUBLICATION rockpub;

-- Option B: Skip initial data copy
-- Only stream changes that happen AFTER the subscription is created
-- Use this when you have already loaded data via pg_dump or another method
CREATE SUBSCRIPTION rocksub
  CONNECTION 'host=<publisher_ip> dbname=your_db user=replication_user password=strong_password port=5432'
  PUBLICATION rockpub
  WITH (copy_data = false);
```

> When `copy_data = true` (default), PostgreSQL automatically:
> 1. Creates a logical replication slot on the publisher
> 2. Takes a consistent snapshot of existing data
> 3. Copies all rows to the subscriber
> 4. Switches to streaming ongoing WAL changes

---

### Step 4 — Verify the Subscription

On the **subscriber**:

```sql
-- List all subscriptions
SELECT
  subname         AS subscription_name,
  subenabled      AS enabled,
  subpublications AS publications,
  subconninfo     AS connection
FROM pg_subscription;

-- Check replication worker status
SELECT *
FROM pg_stat_subscription;
```

On the **publisher**:

```sql
-- Confirm the slot was auto-created by the subscription
SELECT slot_name, plugin, active, confirmed_flush_lsn
FROM pg_replication_slots;

-- Check sender status (publisher side)
SELECT * FROM pg_stat_replication;
```

---

## 5. Managing the Subscription

```sql
-- Pause replication (stop applying changes temporarily)
ALTER SUBSCRIPTION rocksub DISABLE;

-- Resume replication
ALTER SUBSCRIPTION rocksub ENABLE;

-- Add a new publication to an existing subscription
ALTER SUBSCRIPTION rocksub SET PUBLICATION rockpub, another_pub;

-- Refresh after new tables are added to the publication
-- (required when FOR ALL TABLES is NOT used)
ALTER SUBSCRIPTION rocksub REFRESH PUBLICATION;

-- Rename a subscription
ALTER SUBSCRIPTION rocksub RENAME TO my_replica_sub;
```

---

## 6. Dropping the Subscription

> ⚠️ Dropping the subscription **automatically drops the replication slot on the publisher**.
> This is the correct and safe cleanup path — unlike CDC slots which you must drop manually.

```sql
-- On the SUBSCRIBER — drops sub AND its slot on the publisher automatically
DROP SUBSCRIPTION rocksub;

-- Drop only if it exists (safe for scripts)
DROP SUBSCRIPTION IF EXISTS rocksub;

-- Verify it is gone on the subscriber
SELECT subname FROM pg_subscription;

-- Verify the slot is gone on the PUBLISHER
SELECT slot_name FROM pg_replication_slots;
```

> If the subscriber cannot reach the publisher during drop (e.g., publisher is down),
> the local subscription is removed but the **slot on the publisher remains**.
> You must then manually drop it on the publisher:
> ```sql
> -- Run this on the PUBLISHER if the subscriber was dropped while disconnected
> SELECT pg_drop_replication_slot('rocksub');
> ```

---

## 7. Limitations of PostgreSQL Logical Replication

| Limitation | Detail |
|---|---|
| Schema changes NOT replicated | `ALTER TABLE`, `CREATE INDEX` etc. must be run manually on both sides |
| DDL NOT replicated | Only DML (INSERT, UPDATE, DELETE, TRUNCATE) is streamed |
| Sequences NOT replicated | Sequence values are not synced — use `bigserial` carefully on both sides |
| Primary key required for UPDATE/DELETE | Tables without a primary key cannot replicate UPDATE or DELETE |
| No replication of large objects | `pg_largeobject` data is not replicated |
| Subscriber is read-write | Unlike a physical standby, the subscriber allows writes — conflicts are possible |

### Fix: Ensure Tables Have Primary Keys

```sql
-- Check which tables are missing primary keys (they cannot replicate UPDATE/DELETE)
SELECT t.table_schema, t.table_name
FROM information_schema.tables t
LEFT JOIN information_schema.table_constraints tc
  ON  tc.table_schema = t.table_schema
  AND tc.table_name   = t.table_name
  AND tc.constraint_type = 'PRIMARY KEY'
WHERE t.table_type = 'BASE TABLE'
  AND t.table_schema = 'public'
  AND tc.constraint_name IS NULL;
```

---

## 8. Schema Changes — Manual Sync Workflow

Since DDL is not replicated, follow this process for any schema change:

```bash
# 1. Apply the DDL on the PUBLISHER first
psql -h <publisher_ip> -d your_db -U postgres -c "ALTER TABLE orders ADD COLUMN status TEXT;"

# 2. Apply the same DDL on the SUBSCRIBER
psql -h <subscriber_ip> -d your_db -U postgres -c "ALTER TABLE orders ADD COLUMN status TEXT;"

# 3. If a new table was added to a named publication, refresh the subscription
psql -h <subscriber_ip> -d your_db -U postgres -c "ALTER SUBSCRIPTION rocksub REFRESH PUBLICATION;"
```

> For `FOR ALL TABLES` publications: new tables are automatically included on the publisher side.
> You still need to create the table schema on the subscriber manually and run `REFRESH PUBLICATION`.

---

## 9. Quick Reference

```sql
-- PUBLISHER: list publications
SELECT pubname, puballtables FROM pg_publication;

-- PUBLISHER: list active replication slots
SELECT slot_name, active, plugin FROM pg_replication_slots;

-- PUBLISHER: check replication lag (bytes behind)
SELECT
  application_name,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn))  AS send_lag,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn)) AS flush_lag,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS replay_lag
FROM pg_stat_replication;

-- SUBSCRIBER: list subscriptions
SELECT subname, subenabled FROM pg_subscription;

-- SUBSCRIBER: check worker status and last received LSN
SELECT subname, received_lsn, last_msg_send_time, last_msg_receipt_time, latest_end_lsn
FROM pg_stat_subscription;
```

