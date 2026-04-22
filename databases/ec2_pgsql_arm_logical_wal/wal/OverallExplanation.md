https://techcommunity.microsoft.com/blog/adforpostgresql/change-data-capture-in-postgres-how-to-use-logical-decoding-and-wal2json/1396421?utm_source=chatgpt.com

# PostgreSQL WAL & Logical Decoding – Complete Guide

> Source: [Change Data Capture in Postgres – How to use Logical Decoding and wal2json](https://techcommunity.microsoft.com/blog/adforpostgresql/change-data-capture-in-postgres-how-to-use-logical-decoding-and-wal2json/1396421)

---

## 1. What is WAL (Write-Ahead Log)?

WAL is PostgreSQL's **durability mechanism**. Before any data change is written to the actual data files on disk, PostgreSQL first writes a record of that change to the WAL (a sequential log file).

### Why WAL exists

| Problem                          | WAL Solution                                          |
|----------------------------------|-------------------------------------------------------|
| Power loss mid-write             | Replay WAL from last checkpoint on restart            |
| Partial page writes (torn pages) | WAL contains full before/after state                  |
| Need to replicate to standbys    | Standbys consume WAL and apply the same changes       |
| Auditing / Change Data Capture   | WAL records every INSERT, UPDATE, DELETE              |

### How a write works (simplified)

```
Application
    │
    ▼
┌──────────────────────────────────────┐
│  PostgreSQL Backend Process          │
│                                      │
│  1. Generate WAL record              │
│  2. Write WAL record → WAL buffer    │
│  3. Flush WAL buffer → WAL file      │  ← happens BEFORE data file write
│  4. Modify shared buffer (in memory) │
│  5. Background writer flushes to     │
│     data file (asynchronously)       │
└──────────────────────────────────────┘
    │                    │
    ▼                    ▼
WAL Files            Data Files
(pg_wal/)           (base/)
```

> **Key rule:** WAL is always written first. If PostgreSQL crashes, it replays WAL to reconstruct any changes not yet flushed to data files.

---

## 2. WAL Levels

PostgreSQL has three WAL levels, controlled by `wal_level`:

| Level       | What is logged                                   | Use case                          |
|-------------|--------------------------------------------------|-----------------------------------|
| `minimal`   | Only what is needed for crash recovery           | Standalone, no replication        |
| `replica`   | Everything needed for streaming replication      | Physical standbys (default)       |
| `logical`   | Additional info to reconstruct row-level changes | Logical replication, CDC, wal2json |

> ⚠️ **Logical replication requires `wal_level = logical`** — this increases WAL volume slightly but enables CDC.

---

## 3. What is Logical Decoding?

Logical decoding is PostgreSQL's built-in mechanism to **read WAL and convert it into human-readable, row-level change events** (INSERT/UPDATE/DELETE) rather than raw binary blocks.

### Physical vs Logical WAL

| Aspect           | Physical (replica level)         | Logical (logical level)                        |
|------------------|----------------------------------|------------------------------------------------|
| Format           | Raw binary page changes          | Decoded row-level events (INSERT/UPDATE/DELETE)|
| Portability      | Same PostgreSQL major version    | Cross-version, cross-platform                  |
| Use case         | Streaming replication, standbys  | CDC, event streaming, audit logs               |
| Consumer         | Standby PostgreSQL servers       | Any application / Kafka / wal2json             |

### How Logical Decoding Works

```
┌─────────────────────────────────────────────────────┐
│                   PostgreSQL                        │
│                                                     │
│  WAL Files (binary)                                 │
│       │                                             │
│       ▼                                             │
│  Logical Decoding Engine                            │
│  (reads WAL, applies output plugin)                 │
│       │                                             │
│       ▼                                             │
│  Output Plugin (e.g. wal2json, pgoutput, test_decoding) │
│       │                                             │
│       ▼                                             │
│  Replication Slot                                   │
│  (tracks consumer position / LSN)                   │
└──────────────────────┬──────────────────────────────┘
                       │
          ┌────────────┼───────────────┐
          ▼            ▼               ▼
    Your App       Debezium         Custom Consumer
    (pg_recvlogical) (Kafka CDC)    (Python/Node)
```

---

## 4. wal2json Output Plugin

`wal2json` is an output plugin that formats WAL change events as **JSON**, making it easy to consume changes in any language.

### Example output for an INSERT

```json
{
  "change": [
    {
      "kind": "insert",
      "schema": "public",
      "table": "orders",
      "columnnames": ["id", "customer_id", "amount", "created_at"],
      "columntypes": ["integer", "integer", "numeric", "timestamp"],
      "columnvalues": [42, 7, 199.99, "2026-04-22 10:00:00"]
    }
  ]
}
```

### Example output for an UPDATE

```json
{
  "change": [
    {
      "kind": "update",
      "schema": "public",
      "table": "orders",
      "columnnames": ["id", "amount"],
      "columnvalues": [42, 249.99],
      "oldkeys": {
        "keynames": ["id"],
        "keytypes": ["integer"],
        "keyvalues": [42]
      }
    }
  ]
}
```

> **Note:** To capture `oldkeys` (the before-image of an UPDATE/DELETE), tables must have `REPLICA IDENTITY FULL` or a primary key.

---

## 5. Replication Slots

A **replication slot** is a PostgreSQL object that:
- Tracks the **LSN (Log Sequence Number)** position of a consumer
- Ensures WAL files are **retained** until the consumer has read them
- Survives PostgreSQL restarts

### Create a logical replication slot

```sql
-- Using wal2json plugin
SELECT pg_create_logical_replication_slot('my_slot', 'wal2json');

-- Check existing slots
SELECT slot_name, plugin, restart_lsn, confirmed_flush_lsn
FROM pg_replication_slots;
```

### Consume changes from a slot

```bash
# Stream changes live
pg_recvlogical \
  --slot=my_slot \
  --plugin=wal2json \
  --start \
  -f - \
  -d mydb

# Peek without advancing (for testing)
SELECT * FROM pg_logical_slot_peek_changes('my_slot', NULL, NULL);

# Consume and advance the slot position
SELECT * FROM pg_logical_slot_get_changes('my_slot', NULL, NULL);
```

---

## 6. REPLICA IDENTITY – Capturing Old Values

By default, PostgreSQL only logs the **primary key** in UPDATE/DELETE WAL records. To capture the full old row:

| REPLICA IDENTITY | What is stored in WAL              | Recommendation                        |
|------------------|------------------------------------|---------------------------------------|
| `DEFAULT`        | Only primary key columns           | Fine for most CDC use cases           |
| `FULL`           | All columns (before and after)     | Required if no primary key, more WAL  |
| `NOTHING`        | Nothing (UPDATE/DELETE invisible)  | Avoid for CDC                         |
| `USING INDEX`    | Specified unique index columns     | Good compromise                       |

```sql
-- Set full old-row capture
ALTER TABLE orders REPLICA IDENTITY FULL;

-- Check current setting
SELECT relname, relreplident FROM pg_class WHERE relname = 'orders';
```

---

## 7. Common CDC Architecture Using WAL

```
┌─────────────────────────────────┐
│         PostgreSQL              │
│   (wal_level = logical)         │
│                                 │
│   Replication Slot              │
│   (wal2json / pgoutput)         │
└──────────────┬──────────────────┘
               │ WAL events (JSON)
               ▼
┌─────────────────────────────────┐
│   Debezium / pg_recvlogical     │
│   (CDC connector)               │
└──────────────┬──────────────────┘
               │
       ┌───────┴────────┐
       ▼                ▼
┌────────────┐   ┌──────────────┐
│   Kafka    │   │  Your App    │
│  (topic)   │   │  (webhook,   │
│            │   │   audit log) │
└────────────┘   └──────────────┘
```

---

## 8. ⚠️ WAL Growth – The Biggest Risk

> **Replication slots retain WAL until the consumer reads it.**  
> If a consumer stops, WAL accumulates indefinitely and **can fill your disk.**

### How WAL grows out of control

```
Slot created → Consumer reads → WAL released ✅

Slot created → Consumer STOPS → WAL accumulates forever ❌
                                 Disk fills up
                                 PostgreSQL crashes
```

### Monitor WAL retention

```sql
-- Check WAL retained per slot (how far behind each consumer is)
SELECT
  slot_name,
  plugin,
  active,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal_size,
  restart_lsn,
  confirmed_flush_lsn
FROM pg_replication_slots;

-- Check total WAL directory size
SELECT pg_size_pretty(sum(size)) FROM pg_ls_waldir();
```

### WAL Growth Prevention Strategies

| Strategy                              | How                                               |
|---------------------------------------|---------------------------------------------------|
| Monitor slot lag                      | Alert if retained WAL > 1 GB                      |
| Drop unused slots immediately         | `SELECT pg_drop_replication_slot('my_slot');`     |
| Set `max_slot_wal_keep_size`          | PostgreSQL 13+: auto-invalidate lagging slots     |
| Use `wal_keep_size` as a buffer       | Keep N MB of WAL regardless of slots              |
| Consumer health checks                | Alert/restart consumer if it stops reading        |

### WAL retention Calculator

```text
max_slot_wal_keep_size ≈ WAL_per_hour × downtime_tolerance
2GB per hour x 48 hours down time tolerance = 16GB
```

### Safe slot cleanup

```sql
-- Drop a slot (WARNING: consumer will need to re-sync from scratch)
SELECT pg_drop_replication_slot('my_slot');

-- Invalidate a slot that is too far behind (PG 14+)
-- Happens automatically if max_slot_wal_keep_size is set
```

---

## 9. Key postgresql.conf Settings for Logical WAL

```ini
# Required: enable logical decoding
wal_level = logical

# Number of replication slots available (must be >= your slot count)
max_replication_slots = 10

# Number of concurrent WAL sender processes
max_wal_senders = 10

# PostgreSQL 13+: cap how much WAL a slot can retain before auto-invalidation
# Prevents disk-full crashes from lagging consumers
# Set to something like 10 GB in production
max_slot_wal_keep_size = 10GB

# Keep at least this much WAL for emergency
wal_keep_size = 1GB
```

---

## 10. Quick Reference Commands

```sql
-- Create slot
SELECT pg_create_logical_replication_slot('cdc_slot', 'wal2json');

-- List all slots and their lag
SELECT slot_name, active,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS lag
FROM pg_replication_slots;

-- Read changes (non-destructive peek)
SELECT * FROM pg_logical_slot_peek_changes('cdc_slot', NULL, 10,
  'pretty-print', '1', 'add-msg-prefixes', 'wal2json');

-- Read and advance (consume)
SELECT * FROM pg_logical_slot_get_changes('cdc_slot', NULL, 10);

-- Drop slot
SELECT pg_drop_replication_slot('cdc_slot');

-- Check current WAL LSN
SELECT pg_current_wal_lsn();

-- Check WAL directory size
SELECT pg_size_pretty(sum(size)) FROM pg_ls_waldir();
```

---

## 11. Summary Table

| Concept               | Description                                                        |
|-----------------------|--------------------------------------------------------------------|
| WAL                   | Sequential log written before data files; ensures durability       |
| `wal_level = logical` | Enables row-level change decoding on top of crash recovery         |
| Logical Decoding      | Converts binary WAL into readable INSERT/UPDATE/DELETE events      |
| wal2json              | Output plugin that formats changes as JSON                         |
| Replication Slot      | Tracks consumer LSN position; retains WAL until consumed           |
| REPLICA IDENTITY      | Controls what old-row data is captured in WAL for UPDATE/DELETE    |
| WAL retention risk    | Inactive slots cause unbounded WAL growth → disk full → crash      |
| `max_slot_wal_keep_size` | Safety valve: auto-invalidates slots that fall too far behind   |
