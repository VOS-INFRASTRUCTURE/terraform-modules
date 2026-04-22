# PostgreSQL CDC User – Replication + Read-Only Access

> This document covers the exact SQL steps to create a dedicated PostgreSQL
> role for CDC (Change Data Capture) that can:
> - Read WAL via a replication slot (logical decoding)
> - Connect normally via ODBC/JDBC for read-only queries
> - Access all **existing and future** tables automatically

---

## Why a Dedicated User?

Never use your application user or a superuser for CDC. A dedicated role:

| Concern          | Why it matters                                                   |
|------------------|------------------------------------------------------------------|
| **Least privilege** | Only has what CDC needs — no INSERT/UPDATE/DELETE              |
| **Auditability** | All replication activity is traceable to one role               |
| **Safety**       | A compromised CDC credential cannot modify data                 |
| **Separation**   | App user and replication user rotate independently              |

---

## Role Permissions Overview

```
logical_replica_user
        │
        ├── LOGIN                    → can open a connection
        ├── REPLICATION              → can read WAL / create slots
        │
        ├── GRANT CONNECT           → allowed into the target database
        ├── GRANT USAGE ON SCHEMA   → can see tables inside schema
        ├── GRANT SELECT ON TABLES  → read-only query access (ODBC/JDBC)
        └── GRANT USAGE ON SEQUENCES→ read sequence values (optional)
```

---

## Step-by-Step Setup

### Step 1 — Create the Replication Role

```sql
-- Creates a login role with WAL replication permission
-- No superuser — follows least-privilege principle
CREATE ROLE logical_replica_user
  WITH LOGIN
       REPLICATION
       PASSWORD 'use_a_strong_password_here';
```

| Option        | Purpose                                                        |
|---------------|----------------------------------------------------------------|
| `LOGIN`       | Allows the role to open a database connection                  |
| `REPLICATION` | Grants permission to connect in replication mode and use slots |
| No `SUPERUSER`| Best practice — replication does not require superuser         |

> ⚠️ `REPLICATION` is a **cluster-level** privilege, not database-level.
> It is set on the role itself, not via `GRANT`.

---

### Step 2 — Allow Database Connection

```sql
-- Without this the role cannot connect to the target database
-- even though it has LOGIN at the cluster level
GRANT CONNECT ON DATABASE your_db TO logical_replica_user;
```

> Replace `your_db` with your actual database name.
> This must be run while connected to the correct database or as a superuser.

---

### Step 3 — Allow Schema Usage

```sql
-- Allows the role to see and reference objects inside the schema
-- Required before any table-level grants will work
GRANT USAGE ON SCHEMA public TO logical_replica_user;
```

> If you use multiple schemas, repeat this for each one:
> ```sql
> GRANT USAGE ON SCHEMA app, audit, reporting TO logical_replica_user;
> ```

---

### Step 4 — Read Access to All Existing Tables

```sql
-- Grants SELECT on every table currently in the schema
-- This covers all tables that exist at the time this command runs
GRANT SELECT ON ALL TABLES IN SCHEMA public TO logical_replica_user;
```

> ⚠️ This only covers **existing** tables. Tables created later are
> **not** included unless Step 5 is also applied.

---

### Step 5 — Automatically Grant Access to Future Tables ⭐

```sql
-- Automatically grants SELECT to logical_replica_user
-- on every NEW table created in this schema going forward
-- This is the most commonly forgotten step
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO logical_replica_user;
```

> **Important:** `ALTER DEFAULT PRIVILEGES` only applies to tables
> created **by the role that runs this command**. If multiple roles
> create tables in your database (e.g. `app_user`, `migrations_user`),
> you must run this once for each of them:
>
> ```sql
> -- Run as app_user (or SET ROLE app_user first)
> ALTER DEFAULT PRIVILEGES IN SCHEMA public
>   GRANT SELECT ON TABLES TO logical_replica_user;
>
> -- Run as migrations_user
> ALTER DEFAULT PRIVILEGES IN SCHEMA public
>   GRANT SELECT ON TABLES TO logical_replica_user;
> ```
>
> Without this, the CDC user will silently miss new tables created by
> other roles.

---

### Step 6 — Sequence Access (Optional but Common)

Sequences are needed if your consumer reads `currval` / `nextval`, or if
your ODBC client queries sequences directly.

```sql
-- Grant read access to all existing sequences
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO logical_replica_user;

-- Automatically grant access to future sequences
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO logical_replica_user;
```

---

## Complete Script (Copy-Paste Ready)

```sql
-- ============================================================
-- CDC Replication User Setup
-- Run as superuser or database owner
-- Replace: your_db, your_schema, use_a_strong_password_here
-- ============================================================

-- Step 1: Create the role
CREATE ROLE logical_replica_user
  WITH LOGIN
       REPLICATION
       PASSWORD 'use_a_strong_password_here';

-- Step 2: Allow database connection
GRANT CONNECT ON DATABASE your_db TO logical_replica_user;

-- Step 3: Allow schema usage
GRANT USAGE ON SCHEMA public TO logical_replica_user;

-- Step 4: Read access to all existing tables
GRANT SELECT ON ALL TABLES IN SCHEMA public TO logical_replica_user;

-- Step 5: Read access to all FUTURE tables (most important)
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO logical_replica_user;

-- Step 6: Sequence access (existing + future)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO logical_replica_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO logical_replica_user;
```

---

## pg_hba.conf — Allow Replication Connection

The role also needs an entry in `pg_hba.conf` to be allowed to connect
in replication mode (used by Debezium, `pg_recvlogical`, etc.):

```
# pg_hba.conf
# TYPE    DATABASE        USER                    ADDRESS         METHOD
host      replication     logical_replica_user    10.0.0.0/8      scram-sha-256
host      your_db         logical_replica_user    10.0.0.0/8      scram-sha-256
```

| Line          | Purpose                                                      |
|---------------|--------------------------------------------------------------|
| `replication` | Allows the WAL / slot connection (CDC streaming)             |
| `your_db`     | Allows normal ODBC/JDBC read-only query connections          |

> Reload after editing:
> ```bash
> sudo -u postgres psql -c "SELECT pg_reload_conf();"
> # or
> systemctl reload postgresql
> ```

---

## Verify the Setup

```sql
-- Confirm the role exists with correct attributes
SELECT rolname, rolreplication, rolcanlogin
FROM pg_roles
WHERE rolname = 'logical_replica_user';

-- Confirm database connect privilege
SELECT has_database_privilege('logical_replica_user', 'your_db', 'CONNECT');

-- Confirm table read access (test with a specific table)
SELECT has_table_privilege('logical_replica_user', 'public.your_table', 'SELECT');

-- Confirm schema usage
SELECT has_schema_privilege('logical_replica_user', 'public', 'USAGE');

-- List default privileges granted to this role
SELECT * FROM pg_default_acl
WHERE defaclrole = (SELECT oid FROM pg_roles WHERE rolname = 'logical_replica_user');
```

---

## Revoke / Cleanup

```sql
-- Remove default privilege grants
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE SELECT ON TABLES FROM logical_replica_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE USAGE, SELECT ON SEQUENCES FROM logical_replica_user;

-- Revoke existing grants
REVOKE SELECT ON ALL TABLES IN SCHEMA public FROM logical_replica_user;
REVOKE USAGE ON SCHEMA public FROM logical_replica_user;
REVOKE CONNECT ON DATABASE your_db FROM logical_replica_user;

-- Drop the role (only works if no objects are owned by it)
DROP ROLE logical_replica_user;
```

---

## Summary

| Step | SQL | Covers future objects? |
|------|-----|------------------------|
| Create role | `CREATE ROLE ... WITH LOGIN REPLICATION` | — |
| DB connection | `GRANT CONNECT ON DATABASE` | — |
| Schema visibility | `GRANT USAGE ON SCHEMA` | ❌ Manual per schema |
| Existing tables | `GRANT SELECT ON ALL TABLES` | ❌ Existing only |
| **Future tables** | `ALTER DEFAULT PRIVILEGES ... GRANT SELECT ON TABLES` | ✅ Yes |
| Existing sequences | `GRANT USAGE, SELECT ON ALL SEQUENCES` | ❌ Existing only |
| **Future sequences** | `ALTER DEFAULT PRIVILEGES ... GRANT USAGE, SELECT ON SEQUENCES` | ✅ Yes |
| Replication connection | `pg_hba.conf` entry with `replication` database | — |

