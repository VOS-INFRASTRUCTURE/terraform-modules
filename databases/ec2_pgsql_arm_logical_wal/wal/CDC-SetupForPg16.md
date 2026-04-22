# CDC Logical Setup – Step-by-Step Checklist (PostgreSQL 16)

> Target: Enable logical replication / CDC on PostgreSQL 16 running natively on Ubuntu 24.04 ARM64.
> Test with `pg_recvlogical` before connecting any downstream consumer (Debezium, Airbyte, etc).

---

## ✅ Phase 1 — PostgreSQL Parameters

These settings must be in `/etc/postgresql/16/main/postgresql.conf`
(or your custom conf file included from it).

### 1.1 Enable Logical Replication WAL Level

```conf
# Required: WAL must be at logical level for CDC
wal_level = logical
```

> ⚠️ This requires a **PostgreSQL restart** to take effect.
> Without this, replication slots cannot be created.

---

### 1.2 Replication Connection Limits

```conf
# Number of WAL sender processes (= max concurrent slot readers + replicas)
# Rule: set to at least the number of slots you plan to create + 2 buffer
max_wal_senders = 10

# Maximum number of replication slots
# Rule: one slot per CDC consumer + one per standby replica
max_replication_slots = 10
```

---

### 1.3 WAL Keep Size (Baseline WAL Retention)

```conf
# Minimum amount of WAL to keep on disk regardless of replication slots.
# Default: 0 (PostgreSQL only keeps what active slots and checkpoints need)
#
# This is NOT the same as max_slot_wal_keep_size:
#   - wal_keep_size          → minimum WAL floor, kept for standbys WITHOUT slots
#   - max_slot_wal_keep_size → maximum WAL ceiling, caps what slots can retain
#
# For pure CDC (logical slots only, no physical standby):
#   - wal_keep_size = 0 is fine — slots manage their own retention
#   - Setting it to 1GB is a small safety buffer in case a slot temporarily drops
#     and a reconnect needs recent WAL before the slot is recreated
#
# For setups with physical standby replicas (no slots on the standby):
#   - Set to enough WAL to survive a standby lagging during maintenance
#   - 1GB is a reasonable starting point
wal_keep_size = 1GB
```

> **Default:** `0` — PostgreSQL will NOT retain any extra WAL beyond what active
> replication slots and checkpoints require. With slots in place this is usually fine,
> but `1GB` is a low-cost safety net that does not significantly impact disk.

> 💡 `wal_keep_size` accepts units like `1GB`, `512MB` directly in PostgreSQL 13+.
> In PostgreSQL 12 and earlier the setting was called `wal_keep_segments` (a count, not size).

---

### 1.4 WAL Retention Safety Cap (Prevent Disk Runaway)

```conf
# Maximum WAL size to retain for all replication slots combined
# Protects against disk runaway if a slot goes idle or a consumer falls behind
# 16GB is a safe default for most setups — adjust based on your disk
max_slot_wal_keep_size = 16GB
```

> ⚠️ If a slot falls behind and hits this limit, PostgreSQL will **invalidate the slot**.
> Monitor slot lag regularly (see Phase 5).

---

### 1.4 Apply and Restart

```bash
# Verify the config file path
sudo -u postgres psql -c "SHOW config_file;"

# Edit the config
sudo nano /etc/postgresql/16/main/postgresql.conf

# Restart PostgreSQL to apply wal_level change
sudo systemctl restart postgresql

# Confirm wal_level is now logical
sudo -u postgres psql -c "SHOW wal_level;"
# Expected: logical

# Confirm other settings
sudo -u postgres psql -c "SHOW max_wal_senders;"
sudo -u postgres psql -c "SHOW max_replication_slots;"
sudo -u postgres psql -c "SHOW wal_keep_size;"
sudo -u postgres psql -c "SHOW max_slot_wal_keep_size;"
```

---

## ✅ Phase 2 — pg_hba.conf (Allow Replication Connections)

Allow your CDC user to connect for replication:

```bash
sudo nano /etc/postgresql/16/main/pg_hba.conf
```

Add this line (adjust CIDR to your VPC or use `127.0.0.1/32` for local):

```conf
# Allow logical replication user to connect from within the VPC
host    replication     logical_replica_user    10.0.0.0/8    scram-sha-256
```

> If you are testing locally on the same machine, use:
> ```conf
> local   replication     logical_replica_user    trust
> ```

Reload pg_hba without a full restart:

```bash
sudo systemctl reload postgresql
```

---

## ✅ Phase 3 — Create the CDC User

See `LogicalReplicaUserRole.md` for the full breakdown. Quick version:

```sql
-- Connect as superuser
sudo -u postgres psql

-- Create user with replication privilege
CREATE ROLE logical_replica_user
WITH LOGIN REPLICATION PASSWORD 'your_strong_password';

-- Grant access to your database
GRANT CONNECT ON DATABASE your_db TO logical_replica_user;

-- Grant schema usage
GRANT USAGE ON SCHEMA public TO logical_replica_user;

-- Grant read access to ALL existing tables
GRANT SELECT ON ALL TABLES IN SCHEMA public TO logical_replica_user;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO logical_replica_user;

-- Grant access to FUTURE tables automatically
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO logical_replica_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON SEQUENCES TO logical_replica_user;
```

---

## ✅ Phase 4 — Create the Replication Slot

### 4.1 Create a Logical Replication Slot

```sql
-- Connect to your target database (not postgres)
\c your_db

-- Create a slot using wal2json output plugin
-- wal2json decodes WAL changes into JSON
SELECT pg_create_logical_replication_slot('my_cdc_slot', 'wal2json');
```

> **Slot naming convention:** `{env}_{consumer}_{purpose}`
> Example: `staging_airbyte_slot`, `prod_debezium_slot`

> ⚠️ The slot starts capturing changes from the moment it is created.
> It does NOT backfill historical data. Run an initial snapshot on your consumer first if needed.

Available output plugins:
| Plugin | Format | Use Case |
|---|---|---|
| `wal2json` | JSON | Most consumers (Airbyte, custom scripts) |
| `pgoutput` | Binary (native) | Debezium, native logical replication |
| `test_decoding` | Text | Local debugging only |

---

### 4.2 Verify Slot Was Created

```sql
SELECT slot_name, plugin, slot_type, active, restart_lsn, confirmed_flush_lsn
FROM pg_replication_slots;
```

Expected output:
```
   slot_name   |  plugin  | slot_type | active | restart_lsn | confirmed_flush_lsn
---------------+----------+-----------+--------+-------------+---------------------
 my_cdc_slot   | wal2json | logical   | f      | 0/1234ABC   | 0/1234ABC
```

> `active = f` means no consumer is connected yet — that is normal at this stage.

---

## ✅ Phase 5 — Test with pg_recvlogical

`pg_recvlogical` is the built-in PostgreSQL CLI tool to stream logical WAL changes.
It ships with `postgresql-client`.

### 5.1 Install pg_recvlogical (if not already available)

```bash
sudo apt-get install -y postgresql-client-16
pg_recvlogical --version
```

---

### 5.2 Stream Changes to stdout (Live Test)

Open a terminal and run:

```bash
pg_recvlogical \
  --dbname=your_db \
  --username=logical_replica_user \
  --host=127.0.0.1 \
  --port=5432 \
  --slot=my_cdc_slot \
  --plugin=wal2json \
  --start \
  --no-loop \
  -f -
```

> `-f -` → output to stdout.
> `--no-loop` → exit after all buffered changes are flushed (good for testing).
> Remove `--no-loop` for a continuous stream that keeps running.

---

### 5.3 Generate Test Data (In Another Terminal)

```sql
-- Connect to your database
sudo -u postgres psql -d your_db

-- Create a test table if needed
CREATE TABLE IF NOT EXISTS cdc_test (
  id SERIAL PRIMARY KEY,
  name TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert a row
INSERT INTO cdc_test (name) VALUES ('hello cdc');

-- Update a row
UPDATE cdc_test SET name = 'updated' WHERE id = 1;

-- Delete a row
DELETE FROM cdc_test WHERE id = 1;
```

---

### 5.4 Expected Output from pg_recvlogical

You should see JSON like this streaming in the first terminal:

```json
{
  "change": [
    {
      "kind": "insert",
      "schema": "public",
      "table": "cdc_test",
      "columnnames": ["id", "name", "created_at"],
      "columnvalues": [1, "hello cdc", "2026-04-22T10:00:00+00"]
    }
  ]
}
```

> If you see **no output**, the slot position has already passed those LSNs.
> Insert new rows to generate new events.

---

### 5.5 Stream to a File Instead of stdout

```bash
pg_recvlogical \
  --dbname=your_db \
  --username=logical_replica_user \
  --host=127.0.0.1 \
  --port=5432 \
  --slot=my_cdc_slot \
  --plugin=wal2json \
  --start \
  -f /tmp/cdc-output.json
```

Then tail the file in another terminal:

```bash
tail -f /tmp/cdc-output.json
```

---

## ✅ Phase 6 — Monitor Slot Lag

Always monitor your slot after creation. An idle or lagging slot will retain WAL and can fill your disk.

```sql
-- Check all slots and their WAL lag
SELECT
  slot_name,
  plugin,
  active,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_lag,
  restart_lsn,
  confirmed_flush_lsn
FROM pg_replication_slots
ORDER BY wal_lag DESC;
```

> See `MonitoringCDC.md` for full monitoring queries and CloudWatch alerting setup.

---

## ✅ Phase 7 — Drop the Slot (When Done Testing)

> ⚠️ **Always drop unused slots.** An abandoned slot will retain all WAL since creation
> and can fill your disk completely.

```sql
-- Drop the test slot
SELECT pg_drop_replication_slot('my_cdc_slot');

-- Verify it is gone
SELECT slot_name FROM pg_replication_slots;
```

---

## ✅ Phase 8 — Production Slot Setup Checklist

Once testing is complete, use this checklist before going live:

- [ ] `wal_level = logical` confirmed in running PostgreSQL (`SHOW wal_level;`)
- [ ] `max_replication_slots` ≥ number of CDC consumers + replicas
- [ ] `max_wal_senders` ≥ number of CDC consumers + replicas
- [ ] `wal_keep_size = 1GB` set as a safety buffer (default is `0`)
- [ ] `max_slot_wal_keep_size = 16GB` set to prevent disk runaway
- [ ] `pg_hba.conf` allows replication from consumer host/CIDR
- [ ] `logical_replica_user` created with `REPLICATION` privilege
- [ ] Default privileges set so future tables are auto-readable (`ALTER DEFAULT PRIVILEGES`)
- [ ] One slot created per consumer — do NOT share a slot between two consumers
- [ ] Slot lag monitored via CloudWatch or cron-based alert
- [ ] Test insert / update / delete events received and decoded correctly
- [ ] `max_slot_wal_keep_size` behaviour tested in staging (slot invalidation scenario)
- [ ] Downstream consumer configured to resume from last confirmed LSN on reconnect

---

## 📌 Quick Reference — Useful SQL Commands

```sql
-- Check wal_level
SHOW wal_level;

-- List all replication slots
SELECT slot_name, plugin, active, restart_lsn FROM pg_replication_slots;

-- Check WAL lag per slot (human readable)
SELECT slot_name,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_lag
FROM pg_replication_slots;

-- Current WAL position
SELECT pg_current_wal_lsn();

-- Drop a slot
SELECT pg_drop_replication_slot('slot_name');

-- Peek at recent changes WITHOUT advancing the slot position (test_decoding plugin)
SELECT * FROM pg_logical_slot_peek_changes('my_cdc_slot', NULL, NULL);

-- Consume and ADVANCE the slot position
SELECT * FROM pg_logical_slot_get_changes('my_cdc_slot', NULL, NULL);

-- Show disk space used by WAL directory
SELECT pg_size_pretty(sum(size)) FROM pg_ls_waldir();
```

---

## ⚠️ Common Issues

| Problem | Cause | Fix |
|---|---|---|
| `wal_level is not logical` | Config not applied after edit | **Restart** PostgreSQL (reload is not enough) |
| `replication slot already exists` | Slot name collision | Drop the old slot first or use a different name |
| `pg_recvlogical: no output` | No new changes generated after slot creation | Insert new rows to produce events |
| `slot was invalidated` | Slot fell behind `max_slot_wal_keep_size` | Re-create slot; run initial snapshot on consumer |
| `permission denied for replication` | `pg_hba.conf` missing replication entry | Add `host replication user CIDR method` and reload |
| `could not connect to server` | Wrong `--host` or firewall blocking | Check host, port, security group, and pg_hba |
| `FATAL: no pg_hba.conf entry for replication` | pg_hba missing replication line | Add the replication line and reload |
| `wal2json plugin not found` | Plugin not installed | `sudo apt-get install postgresql-16-wal2json` |

