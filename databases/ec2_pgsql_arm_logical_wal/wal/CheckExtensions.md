# wal2json — Check Availability & Installation (PostgreSQL 16 / Ubuntu 24.04)

---

## 1. Check if wal2json is Already Available

Run this SQL as a superuser:

```sql
SELECT *
FROM pg_available_extensions
WHERE name = 'wal2json';
```

> `wal2json` is **not** an extension in the traditional sense — it is a **output plugin**
> loaded by the WAL decoder. The query above may return no rows even when it is installed.

A more reliable check is to look for the shared library directly:

```bash
# Find the installed plugin file
find /usr/lib/postgresql -name "wal2json*"

# Expected output (PostgreSQL 16):
# /usr/lib/postgresql/16/lib/wal2json.so
```

Or test it by creating a temporary slot:

```sql
-- If this succeeds, wal2json is installed
SELECT pg_create_logical_replication_slot('wal2json_test', 'wal2json');

-- Clean up immediately
SELECT pg_drop_replication_slot('wal2json_test');
```

If you get `ERROR: could not access status of transaction` or `unrecognized output plugin "wal2json"`,
the plugin is not installed.

---

## 2. Install wal2json

### Ubuntu 24.04 (PostgreSQL 16 from apt.postgresql.org)

```bash
# Install the wal2json plugin for PostgreSQL 16
sudo apt-get install -y postgresql-16-wal2json

# Verify the .so file is in place
ls /usr/lib/postgresql/16/lib/wal2json.so
```

> **No restart required.** The plugin is loaded dynamically when a slot is created —
> you do not need to add it to `shared_preload_libraries`.

---

### If postgresql.org repo is not configured (vanilla Ubuntu packages)

```bash
# Add the official PostgreSQL apt repository
sudo apt-get install -y curl ca-certificates
sudo install -d /usr/share/postgresql-common/pgdg
curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc

sudo sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

sudo apt-get update

# Now install
sudo apt-get install -y postgresql-16-wal2json
```

---

## 3. Verify Installation

```bash
# Confirm the .so file exists
ls -lh /usr/lib/postgresql/16/lib/wal2json.so

# Check the package version installed
dpkg -l | grep wal2json
```

Then confirm it works from SQL:

```sql
-- Connect to your target database
\c your_db

-- Create a test slot using wal2json
SELECT pg_create_logical_replication_slot('wal2json_check', 'wal2json');

-- Confirm it was created with the correct plugin
SELECT slot_name, plugin FROM pg_replication_slots WHERE slot_name = 'wal2json_check';

-- Drop the test slot immediately
SELECT pg_drop_replication_slot('wal2json_check');
```

Expected output:
```
    slot_name    |  plugin
-----------------+----------
 wal2json_check  | wal2json
```

---

## 4. Add to User Data Script (Terraform Module)

If this PostgreSQL instance is provisioned via the Terraform module, add the installation
to the user data script so it is installed automatically on first boot:

```bash
# Install wal2json alongside postgresql
apt-get install -y postgresql postgresql-contrib postgresql-16-wal2json
```

---

## 5. Other Available Output Plugins (No Install Needed)

These are built into PostgreSQL and require no additional package:

| Plugin | Included | Format | Use Case |
|---|---|---|---|
| `pgoutput` | ✅ Built-in | Binary | Debezium, native logical replication |
| `test_decoding` | ✅ Built-in | Text | Local debugging only |
| `wal2json` | ❌ Requires install | JSON | Airbyte, custom CDC consumers |

> If you only need Debezium, `pgoutput` is built-in and requires no extra packages.
