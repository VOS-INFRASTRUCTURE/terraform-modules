# PostgreSQL WAL & Replication Slots – FAQ

---

### Q1. When I create a new replication slot, does it start from the beginning of WAL history?

**No.** A new replication slot starts reading changes **from the moment it is created**, not from any past WAL history.

```sql
-- The slot's starting LSN is set at creation time
SELECT pg_create_logical_replication_slot('my_new_slot', 'wal2json');

-- confirmed_flush_lsn will reflect the current WAL position at creation
SELECT slot_name, confirmed_flush_lsn FROM pg_replication_slots;
```

> If you need data that existed before the slot was created, you must perform
> an **initial snapshot** (e.g., `pg_dump` or `COPY`) first and then stream
> only the changes that follow.

---

### Q2. If I have two slots — `test_a` (existing) and `test_b` (newly created) — do they share progress?

**No.** Each slot tracks its own position independently.

| Slot     | Behaviour                                                    |
|----------|--------------------------------------------------------------|
| `test_a` | Continues from wherever it last consumed (its own LSN)       |
| `test_b` | Starts fresh from the LSN at the moment it was created       |

Slots do **not** inherit or share progress with each other. Creating `test_b`
has zero effect on `test_a`'s position.

---

### Q3. Can a new slot read changes that an existing slot has already consumed?

**No.** Replication slots do not share, replay, or inherit data from other
slots. Each slot maintains a completely independent read cursor in the WAL.

```
test_a position: LSN 0/50000000  (consumed up to here)
test_b position: LSN 0/8A000000  (starts here — its creation time)

They are entirely independent. test_b cannot "go back" to test_a's history.
```

---

### Q4. How do I capture past data for a new consumer if the slot starts at creation time?

You need an **initial snapshot** before the slot takes over streaming:

```
Step 1: Create the replication slot
        → Note the starting LSN (snapshot LSN)

Step 2: Export a consistent snapshot of current data
        → pg_dump --snapshot=<snapshot_name>
        → or use BEGIN; SET TRANSACTION SNAPSHOT '<id>';

Step 3: Load the snapshot into the consumer

Step 4: Start streaming from the slot's LSN
        → The slot captures all changes that happened after step 1
        → No gap between snapshot and stream
```

Tools like **Debezium** handle this automatically — they call
`CREATE_REPLICATION_SLOT ... EXPORT_SNAPSHOT` to get a consistent starting
point before beginning to stream.

---

### Q5. How does WAL retention work per replication slot?

PostgreSQL retains WAL files **per slot**, based on each slot's individual
read position (`restart_lsn`). A WAL segment is only deleted once **every
active slot** has confirmed it no longer needs that segment.

```sql
-- See each slot's retained WAL
SELECT
  slot_name,
  pg_size_pretty(
    pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)
  ) AS retained_wal
FROM pg_replication_slots;
```

> **Rule:** WAL is deleted based on the **slowest** slot. If one slot is far
> behind, it holds WAL for all the segments it has not yet consumed —
> regardless of how far ahead other slots are.

---

### Q6. Will PostgreSQL delete WAL that a slow consumer has not read yet?

**No — under normal conditions.** PostgreSQL keeps WAL files until **all
active slots** have consumed the data within those files.

```
WAL segment 000000010000000000000042
  ├── test_a consumed ✅  → can be deleted from test_a's perspective
  └── test_b NOT consumed ❌ → segment is RETAINED until test_b reads it
```

This guarantees **no data loss** for a lagging consumer — as long as the
slot remains active and `max_slot_wal_keep_size` is not exceeded.

---

### Q7. What happens if one slot is delayed by 5 minutes while another is up to date?

The delayed slot prevents WAL deletion for its unread portion. Those WAL
segments accumulate on disk for the entire duration of the lag.

```
Timeline (write rate: 100 MB/min):

  test_a: up to date          → retains ~0 MB extra WAL
  test_b: 5 minutes behind    → retains ~500 MB of WAL
                                (100 MB/min × 5 min)

  If test_b stays 5 min behind indefinitely → WAL grows indefinitely ❌
```

> A consumer that is consistently slow (or occasionally pauses) will cause
> steady disk growth. Monitor lag continuously — see `MonitoringCDC.md`.

---

### Q8. Is there any risk of data loss for a lagging consumer under normal conditions?

**No — as long as the slot remains valid.** PostgreSQL's guarantee is:

> *"WAL required by a replication slot will never be removed until the slot
> confirms it has been consumed."*

The slot acts as a bookmark. Even if the database crashes and restarts,
the slot survives and WAL is preserved from the slot's last confirmed LSN.

---

### Q9. What happens if `max_slot_wal_keep_size` is exceeded?

If a slot's accumulated WAL exceeds `max_slot_wal_keep_size`, PostgreSQL
**automatically invalidates** that slot to free disk space and prevent a
crash.

```sql
-- Check if any slots have been invalidated
SELECT slot_name, invalidation_reason
FROM pg_replication_slots
WHERE invalidation_reason IS NOT NULL;
```

| `invalidation_reason` value | Meaning                                              |
|-----------------------------|------------------------------------------------------|
| `wal_removed`               | Slot exceeded `max_slot_wal_keep_size`               |
| `deactivated`               | Slot was administratively deactivated                |
| `primary_demoted`           | Primary was demoted to standby                       |

> ⚠️ Once invalidated, the slot **cannot be resumed**. The consumer must
> re-sync from scratch (new snapshot + new slot). This is why monitoring
> slot lag before it hits the limit is critical.

```ini
# postgresql.conf — set this to prevent disk-full crashes
# Invalidates slots before they consume all disk space
max_slot_wal_keep_size = 10GB
```

---

### Q10. What monitoring should I put in place to avoid disk growth or slot invalidation?

At minimum, monitor these two things continuously:

**1. Slot lag size** — alert before it approaches `max_slot_wal_keep_size`

```sql
SELECT
  slot_name,
  active,
  pg_size_pretty(
    pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)
  ) AS retained_wal
FROM pg_replication_slots
ORDER BY pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) DESC;
```

**2. Disk free space** on the PostgreSQL data volume — alert at 70% used

| Alert Level | Slot Lag        | Disk Used | Action                                    |
|-------------|-----------------|-----------|-------------------------------------------|
| Info        | < 1 GB          | < 50%     | Normal — no action needed                 |
| Warning     | 1 – 5 GB        | 50 – 70%  | Investigate consumer health               |
| Critical    | > 5 GB          | > 70%     | Restart consumer or drop slot immediately |
| Emergency   | Slot invalidated | > 85%    | Drop slot, re-sync consumer, expand disk  |

> For full monitoring automation scripts, CloudWatch alarms, and Terraform
> examples — see [`MonitoringCDC.md`](./MonitoringCDC.md).

