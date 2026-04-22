# PostgreSQL Publications – The Filter Layer for CDC

> A **Publication** sits between WAL and the replication slot. It defines
> **what** data is exposed to consumers — which tables and which operations.
> Without one, logical replication and most CDC tools (including Debezium)
> will not work correctly.

---

## 1. Where Publication Fits in the CDC Stack

```
┌─────────────────────────────────────────────────────┐
│                  PostgreSQL                         │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │             Your Application                  │  │
│  │   INSERT / UPDATE / DELETE on tables          │  │
│  └────────────────────┬──────────────────────────┘  │
│                       │                             │
│                       ▼                             │
│  ┌───────────────────────────────────────────────┐  │
│  │                  WAL                          │  │
│  │   (records every change at binary level)      │  │
│  └────────────────────┬──────────────────────────┘  │
│                       │                             │
│                       ▼                             │
│  ┌───────────────────────────────────────────────┐  │
│  │          PUBLICATION  (filter layer)          │  │ ← defines WHAT
│  │                                               │  │
│  │   • which tables are exposed                  │  │
│  │   • which operations (INSERT/UPDATE/DELETE)   │  │
│  │   • row filters (PostgreSQL 15+)              │  │
│  │   • column filters (PostgreSQL 16+)           │  │
│  └────────────────────┬──────────────────────────┘  │
│                       │                             │
│                       ▼                             │
│  ┌───────────────────────────────────────────────┐  │
│  │         Replication Slot                      │  │ ← tracks WHERE
│  │   (tracks LSN position per consumer)          │  │
│  └────────────────────┬──────────────────────────┘  │
│                       │                             │
└───────────────────────┼─────────────────────────────┘
                        │  decoded change events
                        ▼
          ┌─────────────────────────────┐
          │   Consumer / Debezium / App │
          │   (reads slot via pgoutput  │
          │    or wal2json plugin)      │
          └─────────────────────────────┘
```

---

## 2. Publication vs Replication Slot – Key Distinction

These two are often confused but serve completely different purposes:

| Concept              | Role                           | Analogy                        |
|----------------------|--------------------------------|--------------------------------|
| **Publication**      | Defines **WHAT** is exposed    | A menu of allowed data         |
| **Replication Slot** | Tracks **WHERE** the consumer is in WAL | A bookmark / read cursor |

> They work **together** — a consumer subscribes to a publication
> and reads from a slot. Neither is useful without the other.

---

## 3. Is Publication Only for Replicas?

**No.** This is a very common misconception. Publications serve **two
completely separate use cases**, both of which involve logical decoding:

```
Publication is used by:

  ┌─────────────────────────────────────────────────────────────┐
  │  Use Case 1 – Native Logical Replication (Primary → Replica)│
  │                                                             │
  │  Primary                          Replica                   │
  │  CREATE PUBLICATION app_pub  →    CREATE SUBSCRIPTION sub   │
  │  FOR TABLE orders, users          PUBLICATION app_pub;      │
  │                                                             │
  │  Purpose: keep a second PostgreSQL instance in sync         │
  │  Plugin:  pgoutput (built-in)                               │
  └─────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────┐
  │  Use Case 2 – CDC / Change Data Capture (your use case)     │
  │                                                             │
  │  Primary                          Any Consumer              │
  │  CREATE PUBLICATION cdc_pub  →    Debezium / custom app     │
  │  FOR ALL TABLES                   reads slot with pgoutput  │
  │                                                             │
  │  Purpose: stream change events to Kafka, search, audit, etc │
  │  Plugin:  pgoutput (mandatory) or wal2json (no pub needed)  │
  └─────────────────────────────────────────────────────────────┘
```

The underlying mechanism is identical — both use **logical decoding** and
**replication slots**. The difference is only in who the consumer is:

| Use Case                                        | Consumer              | Plugin used     | Requires Publication?   |
|-------------------------------------------------|-----------------------|-----------------|-------------------------|
| Logical replication (replica)                   | Another PostgreSQL DB | `pgoutput`      | ✅ Yes                  |
| CDC via Debezium                                | Kafka / your app      | `pgoutput`      | ✅ Yes                  |
| CDC via `pg_recvlogical` + `pgoutput`           | Custom consumer / CLI | `pgoutput`      | ✅ Yes                  |
| CDC via `pg_recvlogical` + `wal2json`           | Custom consumer / CLI | `wal2json`      | ❌ No                   |
| CDC via `pg_recvlogical` + `test_decoding`      | Debugging only        | `test_decoding` | ❌ No                   |
| CDC via `wal2json` (direct SQL polling)         | Custom consumer       | `wal2json`      | ❌ No (decodes raw WAL) |

> **Key insight:** `pg_recvlogical` is a **CLI tool**, not a plugin.
> It can stream from a slot using any plugin you specify with `--plugin=`.
> Whether a publication is required depends entirely on **which plugin** it
> is told to use — not on the tool itself:
>
> ```bash
> # Requires a publication (uses pgoutput)
> pg_recvlogical --slot=my_slot --plugin=pgoutput --start -f - -d mydb
>
> # Does NOT require a publication (uses wal2json)
> pg_recvlogical --slot=my_slot --plugin=wal2json --start -f - -d mydb
> ```
>
> The rule is simple: **`pgoutput` always needs a publication.
> `wal2json` and `test_decoding` never do.**

---

## 4. Why Publication is Necessary

Without a publication you **cannot**:

- Use the `pgoutput` plugin (required by Debezium and native logical replication)
- Create a `SUBSCRIPTION` on a replica
- Control which tables or operations are replicated
- Apply row or column filters to reduce WAL traffic

Tools like **Debezium** require a publication to exist (or create one
automatically). `wal2json` is an exception — it does not require a
publication and decodes all tables directly from WAL, but it offers no
filtering at the publication level.

---

## 4. Creating Publications

### 4.1 Replicate All Tables

```sql
-- Expose all tables in the database to consumers
-- Includes INSERT, UPDATE, DELETE, TRUNCATE by default
CREATE PUBLICATION all_tables_pub FOR ALL TABLES;
```

> ✅ **`FOR ALL TABLES` includes future tables automatically.**
> Unlike a named-table publication, this mode does not maintain an explicit
> table list. PostgreSQL resolves "all tables" dynamically at query time —
> any table you `CREATE` **after** this publication is set up is immediately
> included with no further action required.

**Behaviour summary:**

| Scenario                                  | Included? |
|-------------------------------------------|-----------|
| Tables that exist at publication creation | ✅ Yes    |
| Tables created **after** publication      | ✅ Yes    |
| Temporary tables (`CREATE TEMP TABLE`)    | ❌ No     |
| Unlogged tables (`CREATE UNLOGGED TABLE`) | ❌ No     |
| System catalogs (`pg_*`, `information_schema`) | ❌ No |

> ⚠️ **Trade-off:** Because every table is included, a write-heavy database
> with many tables will generate higher WAL volume and the consumer will
> receive changes from tables it may not care about. If you only need a
> subset of tables, use a named-table publication (§4.2) to keep WAL traffic
> lean and consumer processing focused.

### 4.2 Replicate Specific Tables Only

```sql
-- Only expose the tables your consumer actually needs
-- Reduces WAL traffic and consumer processing load
CREATE PUBLICATION orders_pub FOR TABLE orders, order_items, products;
```

### 4.3 Replicate Specific Operations Only

```sql
-- Only stream INSERTs — useful for append-only audit logs
CREATE PUBLICATION inserts_only_pub FOR TABLE events
  WITH (publish = 'insert');

-- Only stream INSERT and UPDATE (ignore DELETEs)
CREATE PUBLICATION no_delete_pub FOR TABLE users, profiles
  WITH (publish = 'insert, update');

-- All operations (default)
CREATE PUBLICATION full_pub FOR TABLE orders
  WITH (publish = 'insert, update, delete, truncate');
```

### 4.4 Row Filters (PostgreSQL 15+)

```sql
-- Only replicate rows where status = 'active'
-- Consumers never see inactive records
CREATE PUBLICATION active_users_pub FOR TABLE users
  WHERE (status = 'active');

-- Only replicate high-value orders
CREATE PUBLICATION large_orders_pub FOR TABLE orders
  WHERE (total_amount > 1000);
```

### 4.5 Column Filters (PostgreSQL 16+)

```sql
-- Only replicate specific columns — exclude PII or large fields
CREATE PUBLICATION safe_users_pub FOR TABLE users
  (id, username, created_at, status);
  -- email, password_hash, phone are NOT replicated
```

---

## 5. How Publication + Slot Work Together (Step by Step)

```
Step 1 – Create the publication (define WHAT)
─────────────────────────────────────────────
  CREATE PUBLICATION app_pub FOR ALL TABLES;

  PostgreSQL now knows which tables and operations to expose.

Step 2 – Create the replication slot (define WHERE to start)
──────────────────────────────────────────────────────────────
  SELECT pg_create_logical_replication_slot('slot_a', 'pgoutput');

  Slot is created at the CURRENT WAL LSN.
  WAL is retained from this point forward.

Step 3 – Consumer connects using both
──────────────────────────────────────
  Consumer specifies:
    - slot name   → "slot_a"       (where to read from)
    - publication → "app_pub"      (what to receive)
    - plugin      → "pgoutput"     (how to decode)

Step 4 – PostgreSQL streams filtered changes
─────────────────────────────────────────────
  Only rows from tables in app_pub
  Only operations allowed in app_pub
  Starting from slot_a's LSN
  Consumer confirms LSN → slot advances → old WAL deleted
```

---

## 6. Managing Publications

### 6.1 List All Publications

```sql
-- Basic list: name, scope, and which operations are published
SELECT
  pubname              AS publication_name,
  puballtables         AS all_tables,
  pubinsert            AS publishes_insert,
  pubupdate            AS publishes_update,
  pubdelete            AS publishes_delete,
  pubtruncate          AS publishes_truncate
FROM pg_publication
ORDER BY pubname;
```

Expected output:
```
 publication_name | all_tables | publishes_insert | publishes_update | publishes_delete | publishes_truncate
------------------+------------+------------------+------------------+------------------+--------------------
 all_tables_pub   | t          | t                | t                | t                | t
 orders_pub       | f          | t                | t                | f                | f
```

```sql
-- Show owner alongside publication details
SELECT
  p.pubname       AS publication_name,
  r.rolname       AS owner,
  p.puballtables  AS all_tables,
  p.pubinsert,
  p.pubupdate,
  p.pubdelete,
  p.pubtruncate
FROM pg_publication p
JOIN pg_roles r ON r.oid = p.pubowner
ORDER BY p.pubname;
```

```sql
-- List which specific tables belong to each publication
-- NOTE: returns no rows for FOR ALL TABLES publications (puballtables = true)
SELECT
  pubname       AS publication_name,
  schemaname,
  tablename
FROM pg_publication_tables
ORDER BY pubname, schemaname, tablename;
```

```sql
-- Combined view: publication + table count (shows 'ALL TABLES' for global ones)
SELECT
  p.pubname AS publication_name,
  CASE
    WHEN p.puballtables THEN 'ALL TABLES (dynamic)'
    ELSE count(pt.tablename)::text || ' table(s)'
  END AS scope
FROM pg_publication p
LEFT JOIN pg_publication_tables pt ON pt.pubname = p.pubname
GROUP BY p.pubname, p.puballtables
ORDER BY p.pubname;
```

---

### 6.2 Alter an Existing Publication

```sql
-- Add a table to an existing named publication
ALTER PUBLICATION orders_pub ADD TABLE payments;

-- Remove a table from a publication
ALTER PUBLICATION orders_pub DROP TABLE old_table;

-- Replace the entire table list
ALTER PUBLICATION orders_pub SET TABLE orders, order_items, payments;

-- Change which operations are published
ALTER PUBLICATION orders_pub SET (publish = 'insert, update');

-- Rename a publication
ALTER PUBLICATION orders_pub RENAME TO transactions_pub;
```

---

### 6.3 Drop (Delete) a Publication

> ⚠️ **Important before dropping:**
> - Dropping a publication does **NOT** drop the replication slot.
> - Any active consumer using `pgoutput` with this publication will **error immediately** on the next read.
> - Any `SUBSCRIPTION` on a replica pointing to this publication will **stop replicating**.
> - If you recreate the publication with the same name, consumers may resume from their last LSN — but there is a risk of a gap in changes during the time it was missing.
> - Always notify or stop consumers **before** dropping a publication.

```sql
-- Drop a single publication
DROP PUBLICATION all_tables_pub;

-- Drop only if it exists (safe for scripts, no error if missing)
DROP PUBLICATION IF EXISTS all_tables_pub;

-- Drop multiple publications at once
DROP PUBLICATION IF EXISTS all_tables_pub, orders_pub, cdc_pub;
```

---

### 6.4 Safe Deletion Workflow

Follow this order to avoid consumer errors:

```sql
-- Step 1: Check which slots are currently active (connected consumers)
SELECT slot_name, active, plugin, confirmed_flush_lsn
FROM pg_replication_slots
WHERE active = true;

-- Step 2: Stop or pause your CDC consumer (Debezium, Airbyte, etc.) first
--         before proceeding. Do NOT drop the publication while active = true.

-- Step 3: Drop the slot BEFORE the publication
--         (prevents orphaned slots accumulating WAL)
SELECT pg_drop_replication_slot('your_slot_name');

-- Step 4: Now safely drop the publication
DROP PUBLICATION IF EXISTS all_tables_pub;

-- Step 5: Verify both are gone
SELECT slot_name FROM pg_replication_slots;
SELECT pubname   FROM pg_publication;
```

> 💡 Drop the **slot first**, then the **publication**.
> Dropping the publication first leaves the slot alive and still accumulating WAL —
> it just cannot serve useful data to `pgoutput` consumers anymore.

---

## 7. Publication + wal2json vs pgoutput

| Feature                   | `wal2json`                        | `pgoutput`                        |
|---------------------------|-----------------------------------|-----------------------------------|
| Requires publication      | ❌ No (decodes all tables from WAL) | ✅ Yes (mandatory)               |
| Output format             | JSON                              | Binary replication protocol       |
| Table filtering           | Not via publication               | ✅ Via publication                |
| Operation filtering       | Not via publication               | ✅ Via publication                |
| Row filters (PG 15+)      | ❌ No                             | ✅ Yes                            |
| Column filters (PG 16+)   | ❌ No                             | ✅ Yes                            |
| Used by Debezium          | Optional                          | ✅ Default (recommended)          |
| Used by native SUBSCRIPTION | ❌ No                           | ✅ Yes                            |

> **Recommendation:** Use `pgoutput` with a named publication for production
> CDC. It gives you fine-grained control and is the native PostgreSQL standard.
> Use `wal2json` only for simple custom consumers that read JSON directly.

---

## 8. Publication in a Native Logical Replication Setup

Publications are also used for **built-in PostgreSQL logical replication**
(not just CDC tools like Debezium):

```
Primary                              Replica
────────                             ───────
CREATE PUBLICATION app_pub           CREATE SUBSCRIPTION app_sub
FOR TABLE orders, users;               CONNECTION 'host=primary ...'
                                       PUBLICATION app_pub;
        │                                      │
        │◀──── WAL streamed via slot ──────────│
        │                                      │
     pg_wal/                           Applies changes
                                       to local tables
```

---

## 9. Common Mistakes

| Mistake                                         | Consequence                                       | Fix                                              |
|-------------------------------------------------|---------------------------------------------------|--------------------------------------------------|
| Using `pgoutput` slot without a publication     | Consumer gets no data / errors                    | `CREATE PUBLICATION` first                       |
| Dropping a publication while slot is active     | Consumer errors on next read                      | Recreate publication or switch consumer to `wal2json` |
| `FOR ALL TABLES` on a write-heavy DB            | High WAL volume, consumer overloaded              | Scope to specific tables only                    |
| No row filter on large tables                   | Consumer processes irrelevant rows                | Add `WHERE` clause (PG 15+)                      |
| Replicating columns with PII unnecessarily      | Data exposure risk in consumer systems            | Use column filters (PG 16+)                      |
| Creating slot without publication first         | Race condition — changes between creation times may be missed | Always create publication before slot |

---

## 10. Quick Reference

```sql
-- Minimal working setup for Debezium / pgoutput CDC
CREATE PUBLICATION cdc_pub FOR ALL TABLES;
SELECT pg_create_logical_replication_slot('cdc_slot', 'pgoutput');

-- Check publication health
SELECT pubname, puballtables, pubinsert, pubupdate, pubdelete
FROM pg_publication;

-- Check slot health
SELECT slot_name, active,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots;

-- See publication + slot used together in pg_stat_replication
SELECT application_name, state, sent_lsn, replay_lsn
FROM pg_stat_replication;
```
