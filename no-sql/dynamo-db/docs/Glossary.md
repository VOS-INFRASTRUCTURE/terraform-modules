# DynamoDB Glossary — For Someone Who Knows Redis/PostgreSQL/MySQL/MS SQL

You know relational databases and Redis well; you've never used DynamoDB. This maps every DynamoDB term used in [CostComparison.md](CostComparison.md) and [Analysis.md](Analysis.md) to the closest thing you already know, plus the gap where the analogy breaks down.

---

## The Basics

| DynamoDB term | Closest thing you know | Where it differs |
|---|---|---|
| **Table** | A table in Postgres/MySQL | No fixed columns. Every row can have different fields — closer to storing JSON blobs, or like a Redis hash where each hash can have different fields. |
| **Item** | A row | Same idea — one item = one record. |
| **Attribute** | A column | Not predefined. You don't `CREATE TABLE` with a column list — only the key columns are declared up front; everything else is free-form per item. |
| **Partition key** (a.k.a. hash key) | The column you'd `SHARD BY` or the key you pick for a Redis key (`user:123`) | This is the **only** required key. DynamoDB uses it to decide which physical partition (shard) stores the item — analogous to how you'd pick a Redis key name to distribute load, or a sharding key in a distributed Postgres setup (Citus, etc.). |
| **Sort key** (a.k.a. range key) | The second column in a composite primary key (`PRIMARY KEY (user_id, created_at)`) | Optional. If present, it lets multiple items share the same partition key but be ordered/queried by range within it — like a clustered index's second column, or like using Redis sorted sets (`ZADD`) to order things under one key. |
| **Primary key** | `PRIMARY KEY` in SQL | = partition key alone, or partition key + sort key together. This is the *only* thing you can't change after table creation (see Analysis.md). |
| **Query vs Scan** | `WHERE indexed_col = X` vs a full table scan | `Query` uses the key schema/index (cheap, fast — like an index seek). `Scan` reads every item (expensive — like `SELECT * FROM table` with no index, or Redis `KEYS *`). Avoid Scan in production the same way you'd avoid a full table scan on a large SQL table. |

---

## Throughput & Capacity

This is the part with no clean SQL analogy, because Postgres/MySQL/MS SQL don't charge per-request — DynamoDB does.

| DynamoDB term | Closest thing you know | Where it differs |
|---|---|---|
| **RCU (Read Capacity Unit)** | Closest is *provisioned IOPS* on an RDS volume, or thinking of Redis's single-threaded ops/sec ceiling | 1 RCU = 1 strongly-consistent read/sec of an item up to 4KB (or 2 eventually-consistent reads/sec of the same). It's a throughput unit you either pre-buy (provisioned) or pay per-use for (on-demand) — there's no equivalent "unit" concept in Postgres, where you just... query, and the DB does what it can with the hardware you gave it. |
| **WCU (Write Capacity Unit)** | Same idea as RCU, for writes | 1 WCU = 1 write/sec of an item up to 1KB. |
| **Provisioned capacity mode** | Sizing a dedicated Redis instance or an RDS instance class for expected load, ahead of time | You declare "I need N WCU/RCU" and pay hourly for that reservation, regardless of whether you use it — like paying for an `m7g.large` whether it's idle or maxed out. |
| **On-demand capacity mode** | No real SQL/Redis equivalent — closest is Aurora Serverless or "pay per query" | No pre-sizing at all; every read/write is billed individually, like a metered utility. DynamoDB scales the underlying capacity for you transparently. |
| **Auto scaling** (provisioned mode) | RDS storage autoscaling, or an HPA in Kubernetes | Automatically raises/lowers your provisioned WCU/RCU based on a target utilization %, so you don't manually resize. |
| **Reserved Capacity** | RDS Reserved Instances | Prepay for 1 or 3 years for a steep discount on provisioned WCU/RCU rates. Same trade-off as RDS RIs: cheaper, but a real commitment. |
| **Eventually consistent read** | Reading from an async replica in Postgres/MySQL (replication lag possible) | Default, cheapest read type; might return slightly stale data (usually sub-second lag). |
| **Strongly consistent read** | Reading from the primary/master | Always returns the latest write; costs 2x an eventually-consistent read. |
| **Transactional read/write** | `BEGIN; ... COMMIT;` — a multi-statement ACID transaction | Groups multiple item operations atomically across tables. Costs 2x the normal request rate — DynamoDB is charging you for the coordination overhead your SQL database gives you "for free" (well, it isn't free there either — it's just billed as part of the instance, not per-transaction). |

---

## Indexes

| DynamoDB term | Closest thing you know | Where it differs |
|---|---|---|
| **GSI (Global Secondary Index)** | `CREATE INDEX` on a non-primary-key column | Functionally similar — lets you query by an attribute other than the primary key. Structurally different: a GSI is really a second, automatically-synced table with its own partition/sort key and its own WCU/RCU billing, not a lightweight B-tree index living inside the same table file. Can be added or dropped after table creation (with a backfill period on large tables, similar in spirit to `CREATE INDEX CONCURRENTLY` taking time on a big Postgres table). |
| **LSI (Local Secondary Index)** | An alternate sort order within a single shard/partition — no direct SQL equivalent | Lets you re-sort items *within the same partition key* by a different sort key. Must be declared at table creation and can never be added/changed later — closest painful analogy is a table partitioning scheme you can't change after data exists. |

---

## Durability, Recovery & Replication

| DynamoDB term | Closest thing you know | Where it differs |
|---|---|---|
| **PITR (Point-in-Time Recovery)** | PITR via WAL replay in Postgres, or binlog replay in MySQL | Same concept: restore the table to any point in the last 35 days. In DynamoDB it's a checkbox, not something you build from WAL archiving yourself. |
| **On-demand backup** | `pg_dump` / a manual RDS snapshot | A manual, full backup you trigger yourself, retained until you delete it. |
| **Streams** | Postgres logical replication slot / MySQL binlog, exposed as a consumable feed | A time-ordered log of every item-level change (insert/update/delete) on the table, readable by Lambda or your own consumer — this is how you'd build CDC (change data capture) pipelines off DynamoDB, the same way you'd tail a binlog off MySQL. |
| **Global Tables** | Multi-master/BDR-style cross-region logical replication in Postgres | Native multi-region, multi-master replication — every region can read and write, with last-writer-wins conflict resolution. No equivalent built into stock Postgres/MySQL; you'd normally need a third-party tool (e.g., pglogical, Galera) to get close. |
| **Table class: Standard vs Standard-IA** | Storage tiering, like moving cold partitions to cheaper storage, or S3 Standard vs Infrequent Access | Same table, same schema — just a billing profile that trades cheaper storage for pricier throughput. Pick Standard-IA only when storage cost dominates (large items, rarely read/written) — similar reasoning to when you'd move a rarely-queried Postgres partition to cheap storage. |
| **DAX (DynamoDB Accelerator)** | **Literally Redis, but managed by AWS specifically for DynamoDB** | You already know this pattern well: DAX sits in front of DynamoDB as a write-through/read cache, same role Redis plays in front of Postgres/MySQL in a typical app stack. Main difference: DAX is API-compatible with the DynamoDB SDK, so your app code barely changes to use it, whereas fronting Postgres with Redis usually means writing your own cache-aside logic. |

---

## Quick Mental Model

If you think of DynamoDB as **"a giant, auto-sharded Redis hash-of-hashes, where the shard key is mandatory, the throughput is metered like a utility bill instead of bound to a server you provisioned, and you get SQL-like secondary indexes bolted on as separate synced tables"** — you're most of the way to an accurate mental model. The biggest adjustment coming from Postgres/MySQL/MS SQL is: there's no query planner doing arbitrary joins or ad-hoc `WHERE` clauses efficiently — you must know your access patterns and design the partition key, sort key, and GSIs around them *before* you have data, much more like designing Redis key structures than designing a normalized relational schema.

---

**Last Updated:** July 2026
