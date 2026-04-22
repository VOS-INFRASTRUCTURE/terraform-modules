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