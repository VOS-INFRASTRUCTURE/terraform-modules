# Redis on EC2 — Direct Installation & Configuration

## Choosing the Right Instance

Redis needs RAM, not CPU. Use memory-optimised `r`-series EC2 instances (Graviton preferred).

> 📄 See **[EC2InstanceSelectionForRedis.md](EC2InstanceSelectionForRedis.md)** for the full instance comparison, pricing tables, Reserved Instance savings, vCPU-to-Redis-instance sizing, EBS volume selection, and CPU pinning.

**Quick picks:**
- 1 app → `r8g.medium` (8 GB, ~$74/mo, ~$33 on 3yr reserved)
- 2–3 apps → `r8g.large` (16 GB, ~$147/mo, ~$65 on 3yr reserved)
- 3–5 apps → `r8g.xlarge` (32 GB, ~$294/mo, ~$130 on 3yr reserved)

---

## Installation on Ubuntu 24.04 (No Docker)

---

## How Many Databases Does Redis Allow?

### The Default: 16 Databases (numbered 0–15)

Redis ships with **16 logical databases** by default, numbered `0` to `15`.

```
Redis Instance
├── DB 0   ← default
├── DB 1
├── DB 2
├── DB 3
├── ...
└── DB 15
```

This is controlled by `databases` in `redis.conf`:

```ini
# /etc/redis/redis.conf
databases 16    # default — can be changed
```

### You Can Increase It

```ini
databases 32    # now DB 0 through DB 31
databases 64    # now DB 0 through DB 63
```

> ⚠️ More databases does **not** use more RAM on its own — empty databases cost nothing. RAM is used only when keys are stored.

### What Is a Redis Database?

A Redis database is a **namespace** — a flat key-value space fully isolated from other databases.

```
DB 0: { "laravel_cache:user:1" → "...", "laravel_cache:products" → "..." }
DB 1: { "laravel_session:abc123" → "...", "laravel_session:xyz789" → "..." }
DB 2: { "laravel_queue:default" → [...], "laravel_queue:failed" → [...] }
DB 3: { "app2_cache:user:1" → "..." }
```

- Keys in DB 0 are **completely invisible** to a client connected to DB 1
- `FLUSHDB` wipes only the current database — not others
- `FLUSHALL` wipes everything across all databases — **never run in production**

---

## How Many Laravel Apps Can Connect?

### Connections Are Unlimited by Default

Redis accepts connections on a **first-come, first-served** basis. The limit is:

```ini
# /etc/redis/redis.conf
maxclients 10000    # default — max simultaneous connections
```

On a 2 GB EC2 instance, each Redis client connection uses approximately **20–50 KB of RAM**.

```
10,000 connections × 50 KB = ~500 MB RAM used just for connections
```

> ✅ For a 2 GB EC2 Redis, a realistic `maxclients` is **500–1000** — leaving the rest for data.

### Multiple Laravel Apps — Connection Reality

Each Laravel request that uses Redis opens a connection. With `phpredis` (persistent connections) or `predis` (non-persistent), this is what happens:

```
Laravel App 1 (ECS — 3 tasks, each with 10 PHP-FPM workers)
    → up to 30 simultaneous Redis connections

Laravel App 2 (ECS — 5 tasks, each with 10 PHP-FPM workers)
    → up to 50 simultaneous Redis connections

Laravel App 3 (ECS — 2 tasks, each with 10 PHP-FPM workers)
    → up to 20 simultaneous Redis connections

Total: ~100 simultaneous connections — well within 10,000 limit
```

### The Real Limit: RAM, Not Connections

On **2 GB RAM** with Redis `maxmemory` set to 1.6 GB:

```
2 GB total RAM
├── OS + Redis process:       ~200 MB
├── Connection overhead:      ~100 MB  (2000 connections × 50KB)
└── Available for data:       ~1.5 GB
```

1.5 GB of Redis data is more than enough for:
- Sessions for 500,000 active users (~3 KB each = 1.5 GB)
- OR cache for a medium-traffic app
- OR both cache + sessions if you keep TTLs tight

---

## Understanding Laravel's Database Numbers (0, 1, etc.)

### Why Laravel Shows 0 or 1

In `config/database.php`, the `database` key selects which Redis logical database to use:

```php
'redis' => [
    'default' => [
        'database' => env('REDIS_DB', 0),         // connects to DB 0
    ],
    'cache' => [
        'database' => env('REDIS_CACHE_DB', 1),   // connects to DB 1
    ],
],
```

Laravel has two named Redis connections by default:
- `default` → used by queues, general `Redis::set()` calls
- `cache` → used by `Cache::put()`, `Cache::remember()`

Both point to the **same Redis instance** but **different database numbers** to avoid key collisions.

### The Problem with Mixing Everything in DB 0

```php
// If everything uses DB 0:
Cache::put('user:1', $data);           // stores key "laravel_cache:user:1" in DB 0
session()->put('cart', $items);        // stores key "laravel_session:abc" in DB 0
dispatch(new ProcessJob($data));       // Horizon stores queue in DB 0

Cache::flush();   // ← WIPES SESSIONS AND QUEUE DATA TOO 💥
```

### Recommended Database Layout for One Laravel App

```
DB 0  → Default (Horizon queues, Redis::set() direct calls)
DB 1  → Cache (Cache::put, Cache::remember, Cache::tags)
DB 2  → Sessions (session driver)
DB 3  → (reserved / future use)
```

```php
// config/database.php
'redis' => [
    'client' => env('REDIS_CLIENT', 'phpredis'),

    'options' => [
        'prefix' => env('REDIS_PREFIX', 'laravel_'),
    ],

    'default' => [
        'host'     => env('REDIS_HOST', '127.0.0.1'),
        'password' => env('REDIS_PASSWORD', null),
        'port'     => env('REDIS_PORT', 6379),
        'database' => env('REDIS_DB', 0),
    ],

    'cache' => [
        'host'     => env('REDIS_HOST', '127.0.0.1'),
        'password' => env('REDIS_PASSWORD', null),
        'port'     => env('REDIS_PORT', 6379),
        'database' => env('REDIS_CACHE_DB', 1),
    ],

    'sessions' => [
        'host'     => env('REDIS_HOST', '127.0.0.1'),
        'password' => env('REDIS_PASSWORD', null),
        'port'     => env('REDIS_PORT', 6379),
        'database' => 2,
    ],
],
```

```env
REDIS_HOST=10.0.1.50
REDIS_PASSWORD=YourStrongPassword!
REDIS_PORT=6379
REDIS_DB=0
REDIS_CACHE_DB=1

CACHE_STORE=redis
SESSION_DRIVER=redis
SESSION_CONNECTION=sessions    # ← tells Laravel to use the 'sessions' connection (DB 2)
```

---

## Multiple Laravel Apps on One Redis Instance

The cleanest pattern is: **one set of database indexes per app**.

```
DB 0  → App 1: default / queues
DB 1  → App 1: cache
DB 2  → App 1: sessions
DB 3  → App 2: default / queues
DB 4  → App 2: cache
DB 5  → App 2: sessions
DB 6  → App 3: default / queues
DB 7  → App 3: cache
DB 8  → App 3: sessions
...
```

With the default `databases 16`, you can host **5 apps** cleanly (3 DB indexes per app = 15 DBs, 1 spare).
With `databases 32`, you can host **10 apps**.

### Per-App Configuration

**App 1 `.env`:**
```env
REDIS_DB=0
REDIS_CACHE_DB=1
# sessions connection → DB 2 in config/database.php
REDIS_PREFIX=app1_
```

**App 2 `.env`:**
```env
REDIS_DB=3
REDIS_CACHE_DB=4
# sessions connection → DB 5 in config/database.php
REDIS_PREFIX=app2_
```

**App 3 `.env`:**
```env
REDIS_DB=6
REDIS_CACHE_DB=7
# sessions connection → DB 8 in config/database.php
REDIS_PREFIX=app3_
```

> ✅ **Always set a unique `REDIS_PREFIX` per app** — even if using different DB indexes. This is a safety layer against key collisions if someone misconfigures a DB number.

### Key Prefix in Action

```
App 1 stores: "app1_user:1:profile"       → in DB 0
App 2 stores: "app2_user:1:profile"       → in DB 3

Even if both accidentally used DB 0:
  "app1_user:1:profile" ≠ "app2_user:1:profile"  ← prefix saves you
```

---

## ✅ Recommended: One Redis Instance Per App

Running separate Redis processes (one per app, each with its own port and password) is the safest approach.

> 📄 See **[SeparateRedisPerApp.md](SeparateRedisPerApp.md)** for the full setup guide including config files, systemd services, firewall rules, memory budgeting, and monitoring.

**Why it's better:**
- App 1 literally **cannot connect** to App 2's Redis — wrong port or wrong password = hard error
- Each app has its own `maxmemory` budget, its own logs, its own restart lifecycle
- All apps use clean identical DB numbering (DB 0, 1, 2) — no coordination needed

---

## Full `redis.conf` for 2 GB RAM EC2

```ini
# /etc/redis/redis.conf

# ── Networking ─────────────────────────────────────
# Bind to private IP only — NEVER 0.0.0.0 in production
bind 10.0.1.50 127.0.0.1
port 6379
protected-mode yes

# ── Authentication ──────────────────────────────────
requirepass YourStrongRedisPassword!

# ── Memory ─────────────────────────────────────────
# Reserve ~200 MB for OS + Redis process overhead
maxmemory 1600mb

# Eviction policy:
# allkeys-lru   → evict least-recently-used keys (good for cache)
# volatile-lru  → only evict keys with TTL set (good for sessions)
# noeviction    → reject writes when full (good for queues)
maxmemory-policy allkeys-lru

# ── Databases ──────────────────────────────────────
databases 16        # DB 0–15, increase if hosting more apps

# ── Persistence ────────────────────────────────────
# RDB snapshot — fast recovery after restart
save 900 1          # save if 1 key changed in 900 seconds
save 300 10         # save if 10 keys changed in 300 seconds
save 60 10000       # save if 10000 keys changed in 60 seconds

# AOF — log every write (more durable than RDB alone)
appendonly yes
appendfsync everysec    # flush AOF every second (good balance)
no-appendfsync-on-rewrite no

# ── Connections ────────────────────────────────────
# On 2 GB RAM: 500-1000 is realistic
maxclients 1000
tcp-keepalive 300

# ── Performance ────────────────────────────────────
hz 20                       # check expiry 20×/sec (default 10)
dynamic-hz yes              # auto-adjust hz under load
lazyfree-lazy-eviction yes  # evict keys in background thread
lazyfree-lazy-expire yes    # expire keys in background thread
lazyfree-lazy-server-del yes

# ── Logging ────────────────────────────────────────
loglevel notice
logfile /var/log/redis/redis-server.log

# ── Disable dangerous commands ─────────────────────
rename-command FLUSHALL ""    # disable FLUSHALL
rename-command FLUSHDB  ""    # disable FLUSHDB
rename-command CONFIG   ""    # disable CONFIG (re-enable if needed)
rename-command DEBUG    ""    # disable DEBUG
```

> ✅ `rename-command FLUSHALL ""` — this permanently disables `FLUSHALL` so a misconfigured app or attacker cannot wipe all data.

---

## How Much RAM Do You Actually Need?

### 2 GB RAM Capacity Estimates

| Workload | RAM per item | 2 GB capacity |
|---|---|---|
| Sessions (typical Laravel) | ~3–5 KB | ~300,000–500,000 active sessions |
| Cache entries (small) | ~1–5 KB | ~300,000–1,000,000 entries |
| Cache entries (large, 50 KB avg) | ~50 KB | ~30,000 entries |
| Horizon job queue entries | ~2–10 KB | ~150,000–750,000 queued jobs |
| Rate limiter counters | ~100 bytes | ~15,000,000 counters |

### Monitoring Memory Usage

```bash
# Connect to Redis CLI
redis-cli -h 10.0.1.50 -a YourStrongRedisPassword!

# Memory stats
INFO memory

# Output includes:
# used_memory_human: 45.23M      ← actual data size
# used_memory_rss_human: 62.00M  ← OS-allocated (includes fragmentation)
# maxmemory_human: 1.56G         ← your limit
# mem_fragmentation_ratio: 1.37  ← above 1.5 = high fragmentation (restart helps)

# Check per-database key count
INFO keyspace
# db0:keys=12453,expires=8921,avg_ttl=3600000
# db1:keys=45231,expires=45000,avg_ttl=86400000
# db2:keys=8821,expires=8821,avg_ttl=7200000

# Slow query log
SLOWLOG GET 10     # last 10 slow commands

# Check connected clients
CLIENT LIST
INFO clients
# connected_clients: 87
# blocked_clients: 0
```

---

## Summary

| Question | Answer |
|---|---|
| How many databases per instance? | **16 by default** (DB 0–15), configurable via `databases N` in conf |
| What is DB 0, 1, 2? | **Logical namespaces** — fully isolated key-value spaces within one process |
| How many apps can connect? | **Unlimited** (default max 10,000 connections) — RAM is the real limit |
| Shared instance vs separate per app? | **Separate per app is safer** — different port + different password = impossible to misconfigure |
| Can App 1 accidentally connect to App 2? | ❌ Not possible with separate ports + passwords |
| How many Redis processes on 2 GB EC2? | **3 comfortably** (~450 MB each, OS gets 200 MB, process overhead ~150 MB) |
| Each app's DB numbering with separate instances? | All apps use `DB 0` (cache), `DB 1` (sessions) — clean, no juggling |
| 2 GB RAM — how many sessions per app? | ~**100,000–150,000 active sessions** per app (at 450 MB each) |
| How to prevent `FLUSHDB` accidents? | `rename-command FLUSHDB ""` in each conf file |
| How to monitor all instances? | `redis-cli -p 6379/6380/6381 INFO` per instance |

---

*Last updated: May 12, 2026*

