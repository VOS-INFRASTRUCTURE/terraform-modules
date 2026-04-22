# PostgreSQL CDC Architecture – WAL Logical Decoding

---

## 1. High-Level Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        PostgreSQL (Primary)                         │
│                      wal_level = logical                            │
│                                                                     │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────────────────┐  │
│  │  Your App   │   │  Data Files │   │        WAL Files         │  │
│  │ (writes)    │──▶│  (base/)    │   │       (pg_wal/)          │  │
│  └─────────────┘   └─────────────┘   └──────────┬──────────────┘  │
│                                                  │                  │
│                         ┌────────────────────────┘                  │
│                         │  Logical Decoding Engine                  │
│                         │  (output plugin: wal2json / pgoutput)     │
│                         │                                           │
│              ┌──────────┴──────────┐                               │
│              │  Replication Slots  │                               │
│              │  slot_a  │  slot_b  │  (each tracks own LSN)       │
│              └──────────┴──────────┘                               │
└────────────────────┬──────────────────────────────────────────────┘
                     │ decoded row-level change events (JSON)
                     │ INSERT / UPDATE / DELETE + before & after values
                     ▼
```

---

## 2. Deployment Patterns

### Pattern A – Direct Application Consumption (Lightweight)

Best for: small teams, simple use cases, no Kafka infrastructure.

```
┌─────────────────────────────────────────────┐
│              PostgreSQL                     │
│         (wal_level = logical)               │
│                                             │
│   Replication Slot: app_cdc_slot            │
│   Plugin: wal2json                          │
└─────────────────┬───────────────────────────┘
                  │  pg_logical_slot_get_changes()
                  │  or pg_recvlogical (streaming)
                  ▼
┌─────────────────────────────────────────────┐
│         Consumer Application                │
│   (Node.js / Python / Go)                  │
│                                             │
│   - Polls or streams changes via SQL        │
│   - Processes events in-process            │
│   - Commits LSN after successful processing │
└──────────┬─────────────────┬───────────────┘
           │                 │
           ▼                 ▼
    ┌─────────────┐   ┌─────────────────┐
    │  Audit Log  │   │  Cache / Search  │
    │  (DB table) │   │  (Redis/ES)      │
    └─────────────┘   └─────────────────┘
```

---

### Pattern B – Debezium + Kafka (Production / Event Streaming)

Best for: microservices, high-volume writes, multiple downstream consumers.

```
┌──────────────────────────────────────────────────────────────────┐
│                       PostgreSQL (Primary)                       │
│                      wal_level = logical                         │
│                                                                  │
│              Replication Slot: debezium_slot                     │
│              Plugin: pgoutput  (or wal2json)                     │
└──────────────────────────┬───────────────────────────────────────┘
                           │  streaming replication protocol
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Debezium Connector                            │
│              (runs inside Kafka Connect)                         │
│                                                                  │
│  - Manages slot creation & LSN tracking                          │
│  - Handles initial snapshot automatically                        │
│  - Converts WAL events → Kafka messages                          │
│  - Retries on failure without data loss                          │
└──────────────────────────┬───────────────────────────────────────┘
                           │  Kafka messages (Avro / JSON)
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│                        Apache Kafka                              │
│                                                                  │
│   Topic: postgres.public.orders                                  │
│   Topic: postgres.public.users                                   │
│   Topic: postgres.public.products                                │
│                                                                  │
│   (one topic per table, partitioned by primary key)              │
└───────┬──────────────┬──────────────┬──────────────┬────────────┘
        │              │              │              │
        ▼              ▼              ▼              ▼
┌────────────┐  ┌────────────┐  ┌──────────┐  ┌──────────────┐
│  Search    │  │  Analytics │  │  Cache   │  │  Audit /     │
│  (ES /     │  │  (Flink /  │  │  Warm-up │  │  Compliance  │
│  OpenSearch│  │  Spark)    │  │  (Redis) │  │  (S3 / DB)   │
└────────────┘  └────────────┘  └──────────┘  └──────────────┘
```

---

### Pattern C – pg_recvlogical (Lightweight Streaming, No Kafka)

Best for: simple pipelines, file exports, webhook forwarding.

```
┌──────────────────────────────────┐
│          PostgreSQL              │
│     Replication Slot (wal2json)  │
└──────────────┬───────────────────┘
               │  binary replication stream
               ▼
┌──────────────────────────────────┐
│        pg_recvlogical            │
│  (CLI tool, runs on same server  │
│   or a separate consumer host)   │
└──────────────┬───────────────────┘
               │  newline-delimited JSON to stdout
               ▼
   ┌───────────┴────────────┐
   ▼                        ▼
┌──────────┐         ┌────────────────┐
│  File /  │         │  Custom Script │
│  S3      │         │  (filter, route│
│  Archive │         │   transform)   │
└──────────┘         └────────────────┘
```

---

## 3. Multi-Slot Architecture (Multiple Consumers)

Each consumer gets its **own independent slot** so each tracks its own LSN.

```
                  PostgreSQL
           (wal_level = logical)
                     │
        ┌────────────┼────────────┐
        │            │            │
        ▼            ▼            ▼
  ┌──────────┐ ┌──────────┐ ┌──────────┐
  │  slot_a  │ │  slot_b  │ │  slot_c  │
  │ (Debezium│ │ (Analytics│ │ (Audit   │
  │  / Kafka)│ │ pipeline) │ │  app)    │
  └────┬─────┘ └────┬──────┘ └────┬─────┘
       │             │              │
       ▼             ▼              ▼
  Kafka Topics   ClickHouse     Audit DB

⚠️  WAL is retained until the SLOWEST slot has consumed it.
    Monitor all slots — one dead slot blocks WAL cleanup for ALL.
```

---

## 4. WAL Flow Inside PostgreSQL

```
 Application WRITE (INSERT / UPDATE / DELETE)
        │
        ▼
 ┌──────────────────────────────────────────────┐
 │              Shared Memory                   │
 │                                              │
 │  ┌──────────────┐     ┌──────────────────┐   │
 │  │ Shared Buffer│     │   WAL Buffer     │   │
 │  │ (data pages) │     │ (wal records)    │   │
 │  └──────┬───────┘     └────────┬─────────┘   │
 │         │                      │              │
 └─────────┼──────────────────────┼──────────────┘
           │                      │
           │              ① WAL flushed to disk FIRST
           │                      │
           ▼                      ▼
    ┌──────────────┐      ┌──────────────────┐
    │  Data Files  │      │   WAL Files      │
    │  (async      │      │   (pg_wal/)      │
    │   write)     │      │                  │
    └──────────────┘      └────────┬─────────┘
                                   │
                      ② Logical Decoding Engine reads WAL
                                   │
                          ┌────────┴──────────┐
                          │  Output Plugin    │
                          │  (wal2json /      │
                          │   pgoutput)       │
                          └────────┬──────────┘
                                   │
                      ③ Decoded events sent to consumer
                         via Replication Slot
                                   │
                          ┌────────┴──────────┐
                          │  Consumer reads,  │
                          │  confirms LSN     │
                          │  (slot advances)  │
                          └───────────────────┘
                                   │
                      ④ Old WAL segments deleted
                         (once ALL slots have advanced past them)
```

---

## 5. Initial Snapshot + Streaming Handoff

A new slot only captures changes **from creation time forward**.
To backfill existing data, use the exported snapshot during slot creation:

```
Time ──────────────────────────────────────────────────────────────▶

  T0: Slot created (snapshot LSN = 0/5A000000)
       │
       │   ┌──────────────────────────────┐
       │   │  pg_dump --snapshot=<id>     │  ← consistent export
       │   │  (reads data at T0 LSN)      │     of existing rows
       │   └──────────────────┬───────────┘
       │                      │
       │                      ▼
       │              Load into consumer
       │
  T1:  └─── Slot begins streaming changes AFTER T0
             (no gap — slot held WAL since T0)
             │
             ▼
          Consumer applies changes on top of snapshot
          ✅ Full consistent view, no data loss
```

---

## 6. Failure & Recovery Scenarios

```
Scenario 1 – Consumer restarts cleanly
─────────────────────────────────────
  Consumer crashes at LSN 0/60000000
       │
       │  Slot retains WAL from 0/60000000
       │
  Consumer restarts → reconnects to slot
       │
       └─▶ Resumes from 0/60000000 ✅
           No data loss

Scenario 2 – Consumer down for too long (exceeds max_slot_wal_keep_size)
─────────────────────────────────────────────────────────────────────────
  Consumer down for 2 hours
  WAL accumulates → exceeds max_slot_wal_keep_size (e.g. 10 GB)
       │
       └─▶ PostgreSQL INVALIDATES the slot ❌
           Consumer reconnects → ERROR: slot invalidated
           Must re-sync: new snapshot + new slot

Scenario 3 – PostgreSQL crashes and restarts
─────────────────────────────────────────────
  PostgreSQL crashes
       │
       └─▶ Replays WAL for crash recovery (REDO)
           Replication slots survive the restart ✅
           Consumers reconnect → resume from confirmed LSN
```

---

## 7. AWS Deployment Architecture (EC2 + Private Subnet)

```
┌──────────────────────────────────────────────────────────────────────┐
│                          AWS VPC (Private Subnet)                    │
│                                                                      │
│  ┌─────────────────────────┐      ┌─────────────────────────────┐   │
│  │  EC2 – PostgreSQL ARM   │      │  EC2 – Consumer App         │   │
│  │  (t4g.medium / large)   │      │  (Node.js / Python / Java)  │   │
│  │                         │      │                             │   │
│  │  wal_level = logical    │◀─────│  pg_recvlogical / Debezium  │   │
│  │  Replication Slot       │      │  reads slot over port 5432  │   │
│  │  wal2json plugin        │      └─────────────┬───────────────┘   │
│  └──────────┬──────────────┘                    │                   │
│             │                                   │                   │
│             │ Secrets Manager endpoint           │                   │
│             │ S3 Interface endpoint              ▼                   │
│             │                        ┌──────────────────────┐       │
│             └───────────────────────▶│  Amazon MSK (Kafka)  │       │
│                                      │  or SQS / EventBridge│       │
│                                      └──────────┬───────────┘       │
└─────────────────────────────────────────────────┼────────────────────┘
                                                  │
                              ┌───────────────────┼──────────────────┐
                              ▼                   ▼                  ▼
                    ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
                    │  OpenSearch  │   │  S3 / Athena │   │  DynamoDB    │
                    │  (full-text) │   │  (analytics) │   │  (cache)     │
                    └──────────────┘   └──────────────┘   └──────────────┘
```

---

## 8. Output Plugin Comparison

| Plugin          | Format       | Schema info | Old row values | Use case                          |
|-----------------|--------------|-------------|----------------|-----------------------------------|
| `wal2json`      | JSON         | ✅ Yes       | ✅ With REPLICA IDENTITY FULL | General CDC, easy to consume |
| `pgoutput`      | Binary proto | ✅ Yes       | ✅ With REPLICA IDENTITY FULL | Debezium, logical replication |
| `test_decoding` | Text         | ❌ Limited   | ❌ No          | Debugging / testing only          |

---

## 9. Key Design Principles

| Principle                        | Why it matters                                                   |
|----------------------------------|------------------------------------------------------------------|
| One slot per consumer            | Independent progress tracking; one slow consumer doesn't block others (only WAL deletion) |
| Always set `max_slot_wal_keep_size` | Prevents disk-full crash from dead consumers                  |
| Monitor slot lag continuously    | Catch runaway WAL before it fills disk                           |
| Initial snapshot before streaming | Ensures no gap between historical data and live changes         |
| Use `REPLICA IDENTITY FULL` carefully | Increases WAL volume — only use on tables that need old values |
| Confirm LSN only after processing | Never advance the slot before the event is safely stored        |
