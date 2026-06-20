# Redis on EC2 — One Instance Per App (Separate Ports & Passwords)

## Why Separate Instances Are Safer Than Shared Databases

With a shared Redis instance, apps are separated only by DB number and key prefix.
A misconfigured `REDIS_DB` or `REDIS_PORT` silently connects to the wrong app's data with no error.

With separate Redis processes, the wrong port or password gives an **immediate hard error** — impossible to silently cross-contaminate.

```
Shared instance (DB numbers only):
  App 2 misconfigures REDIS_DB=0  →  silently reads App 1's data 💥

Separate instances (port + password):
  App 2 misconfigures REDIS_PORT=6379  →  WRONGPASS error ✅  connection refused ✅
```

### Comparison

| | Shared Instance (DB numbers) | Separate Instances (per app) |
|---|---|---|
| Misconfiguration risk | Wrong `REDIS_DB` → reads wrong app's data silently | Wrong port or password → hard error ✅ |
| Password isolation | One password grants access to all apps | Each app has its own unique password ✅ |
| `FLUSHDB` blast radius | Only clears that DB index | Only clears that app's entire Redis ✅ |
| `maxmemory` control | One shared pool | Per-app memory budget ✅ |
| Restart impact | Restart affects all apps | Restart only that app's process ✅ |
| Monitoring clarity | Mixed metrics from all apps | Per-app metrics and logs ✅ |
| Security breach | One compromised app → all Redis data exposed | Compromised app sees only its own Redis ✅ |
| DB number juggling | App1=DB0, App2=DB3, App3=DB6... | All apps use DB 0 for default, DB 1 for cache ✅ |

---

## Architecture

```
EC2 Redis Host (10.0.1.50)
├── redis-app1  port 6379  password: App1$trongPass!  maxmemory: 450mb
│     DB 0 → queues/default
│     DB 1 → cache
│     DB 2 → sessions
│
├── redis-app2  port 6380  password: App2$trongPass!  maxmemory: 450mb
│     DB 0 → queues/default
│     DB 1 → cache
│     DB 2 → sessions
│
└── redis-app3  port 6381  password: App3$trongPass!  maxmemory: 450mb
      DB 0 → queues/default
      DB 1 → cache
      DB 2 → sessions
```

Each app uses clean, identical DB numbering (`0`, `1`, `2`) — no coordination needed.

---

## Step 1: Create Directories

```bash
# Config files
sudo mkdir -p /etc/redis

# Separate data dirs per app — AOF and RDB files stay isolated
sudo mkdir -p /var/lib/redis/app1 \
              /var/lib/redis/app2 \
              /var/lib/redis/app3

# Logs
sudo mkdir -p /var/log/redis

# PID files dir
sudo mkdir -p /var/run/redis

sudo chown -R redis:redis /var/lib/redis /var/log/redis /var/run/redis
```

---

## Step 2: Config File Per App

### `/etc/redis/app1.conf` — Port 6379

```ini
# ── Network ────────────────────────────────────────
port 6379
bind 10.0.1.50 127.0.0.1     # private EC2 IP only — no public access
protected-mode yes
tcp-keepalive 300

# ── Security ────────────────────────────────────────
requirepass App1$trongRedisPass!

# ── Files ───────────────────────────────────────────
dir /var/lib/redis/app1
dbfilename dump-app1.rdb
pidfile /var/run/redis/redis-app1.pid

# ── Memory ──────────────────────────────────────────
# 2 GB host, 3 apps: 450 MB each
# OS + processes use ~350 MB → 3 × 450 = 1,350 MB + 350 MB = 1,700 MB ✅
maxmemory 450mb

# allkeys-lru  → good for cache (evict least-recently-used)
# volatile-lru → good for sessions (only evict keys with TTL)
# noeviction   → good for queues (reject writes instead of evicting)
maxmemory-policy allkeys-lru

# ── Databases ───────────────────────────────────────
# Each app only needs 4 DBs maximum — no reason to carry 16
databases 4

# ── Persistence ─────────────────────────────────────
# RDB — periodic snapshot (fast restart recovery)
save 900 1
save 300 10
save 60 10000

# AOF — log each write (durable against crash between snapshots)
appendonly yes
appendfilename "appendonly-app1.aof"
appendfsync everysec

# ── Performance ─────────────────────────────────────
hz 20
dynamic-hz yes
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes

# ── Connections ─────────────────────────────────────
maxclients 500      # per app — 500 × 3 apps = 1500 max total

# ── Logging ─────────────────────────────────────────
loglevel notice
logfile /var/log/redis/app1.log

# ── Disable dangerous commands ──────────────────────
rename-command FLUSHALL  ""
rename-command FLUSHDB   ""
rename-command CONFIG    ""
rename-command DEBUG     ""
rename-command SLAVEOF   ""
rename-command REPLICAOF ""
```

---

### `/etc/redis/app2.conf` — Port 6380

```ini
port 6380
bind 10.0.1.50 127.0.0.1
protected-mode yes
tcp-keepalive 300

requirepass App2$trongRedisPass!

dir /var/lib/redis/app2
dbfilename dump-app2.rdb
pidfile /var/run/redis/redis-app2.pid

maxmemory 450mb
maxmemory-policy allkeys-lru

databases 4

save 900 1
save 300 10
save 60 10000

appendonly yes
appendfilename "appendonly-app2.aof"
appendfsync everysec

hz 20
dynamic-hz yes
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes

maxclients 500

loglevel notice
logfile /var/log/redis/app2.log

rename-command FLUSHALL  ""
rename-command FLUSHDB   ""
rename-command CONFIG    ""
rename-command DEBUG     ""
rename-command SLAVEOF   ""
rename-command REPLICAOF ""
```

---

### `/etc/redis/app3.conf` — Port 6381

```ini
port 6381
bind 10.0.1.50 127.0.0.1
protected-mode yes
tcp-keepalive 300

requirepass App3$trongRedisPass!

dir /var/lib/redis/app3
dbfilename dump-app3.rdb
pidfile /var/run/redis/redis-app3.pid

maxmemory 450mb
maxmemory-policy allkeys-lru

databases 4

save 900 1
save 300 10
save 60 10000

appendonly yes
appendfilename "appendonly-app3.aof"
appendfsync everysec

hz 20
dynamic-hz yes
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes

maxclients 500

loglevel notice
logfile /var/log/redis/app3.log

rename-command FLUSHALL  ""
rename-command FLUSHDB   ""
rename-command CONFIG    ""
rename-command DEBUG     ""
rename-command SLAVEOF   ""
rename-command REPLICAOF ""
```

---

## Step 3: Systemd Service Per App

### `/etc/systemd/system/redis-app1.service`

```ini
[Unit]
Description=Redis In-Memory Store — App1 (port 6379)
After=network.target
Documentation=https://redis.io/docs

[Service]
Type=forking
ExecStart=/usr/bin/redis-server /etc/redis/app1.conf
ExecStop=/usr/bin/redis-cli -h 10.0.1.50 -p 6379 -a 'App1$trongRedisPass!' shutdown nosave
PIDFile=/var/run/redis/redis-app1.pid
TimeoutStartSec=30
TimeoutStopSec=30
Restart=always
RestartSec=5
User=redis
Group=redis
RuntimeDirectory=redis
RuntimeDirectoryMode=0755
UMask=007
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

Create identical files for `redis-app2.service` (port 6380) and `redis-app3.service` (port 6381) — just change the port, password, and conf path.

```bash
# Enable and start all three
sudo systemctl daemon-reload
sudo systemctl enable  redis-app1 redis-app2 redis-app3
sudo systemctl start   redis-app1 redis-app2 redis-app3

# Check all are running
sudo systemctl status  redis-app1 redis-app2 redis-app3
```

---

## Step 4: Verify Isolation

```bash
# Confirm all 3 ports are listening on private IP only
ss -tlnp | grep redis
# LISTEN  10.0.1.50:6379  ...  redis-app1
# LISTEN  10.0.1.50:6380  ...  redis-app2
# LISTEN  10.0.1.50:6381  ...  redis-app3

# Each responds to its own password
redis-cli -h 10.0.1.50 -p 6379 -a 'App1$trongRedisPass!' ping    # PONG ✅
redis-cli -h 10.0.1.50 -p 6380 -a 'App2$trongRedisPass!' ping    # PONG ✅
redis-cli -h 10.0.1.50 -p 6381 -a 'App3$trongRedisPass!' ping    # PONG ✅

# Wrong password on App1's port → hard reject
redis-cli -h 10.0.1.50 -p 6379 -a 'App2$trongRedisPass!' ping
# (error) WRONGPASS invalid username-password pair ✅

# Wrong password on App2's port → hard reject
redis-cli -h 10.0.1.50 -p 6380 -a 'App1$trongRedisPass!' ping
# (error) WRONGPASS invalid username-password pair ✅
```

---

## Step 5: Laravel `.env` Per App

Each app's `.env` only knows its own port and password.
Even if a developer copies the wrong `.env` by mistake, the connection will be refused.

**App 1 `.env`:**
```env
REDIS_HOST=10.0.1.50
REDIS_PORT=6379
REDIS_PASSWORD=App1$trongRedisPass!
REDIS_DB=0
REDIS_CACHE_DB=1

CACHE_STORE=redis
SESSION_DRIVER=redis
SESSION_CONNECTION=sessions
```

**App 2 `.env`:**
```env
REDIS_HOST=10.0.1.50
REDIS_PORT=6380
REDIS_PASSWORD=App2$trongRedisPass!
REDIS_DB=0
REDIS_CACHE_DB=1

CACHE_STORE=redis
SESSION_DRIVER=redis
SESSION_CONNECTION=sessions
```

**App 3 `.env`:**
```env
REDIS_HOST=10.0.1.50
REDIS_PORT=6381
REDIS_PASSWORD=App3$trongRedisPass!
REDIS_DB=0
REDIS_CACHE_DB=1

CACHE_STORE=redis
SESSION_DRIVER=redis
SESSION_CONNECTION=sessions
```

### Laravel `config/database.php` — Same for All Apps

```php
'redis' => [
    'client' => env('REDIS_CLIENT', 'phpredis'),

    'options' => [
        'prefix' => env('REDIS_PREFIX', Str::slug(env('APP_NAME', 'laravel'), '_').'_'),
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

> ✅ `APP_NAME` auto-generates the prefix — App 1 keys: `my_app_cache:user:1`, App 2 keys: `billing_app_cache:user:1`.  
> This is an extra safety layer even with separate instances.

---

## Step 6: Firewall — AWS Security Groups

If each Laravel app's ECS tasks are in a different Security Group:

```
App1 ECS SG  →  Inbound TCP 6379  →  Redis EC2 SG   (App1 only)
App2 ECS SG  →  Inbound TCP 6380  →  Redis EC2 SG   (App2 only)
App3 ECS SG  →  Inbound TCP 6381  →  Redis EC2 SG   (App3 only)
```

App1's ECS tasks have no outbound rule for port 6380 or 6381 — even if a developer hardcodes the wrong port, the network layer blocks it before Redis even sees the connection.

**UFW on the EC2 (extra layer):**

```bash
# Only allow each app subnet to its own port
sudo ufw allow from 10.0.10.0/24 to any port 6379 comment "App1 Redis"
sudo ufw allow from 10.0.20.0/24 to any port 6380 comment "App2 Redis"
sudo ufw allow from 10.0.30.0/24 to any port 6381 comment "App3 Redis"

# Deny everything else on Redis ports
sudo ufw deny 6379
sudo ufw deny 6380
sudo ufw deny 6381

sudo ufw enable
sudo ufw status verbose
```

---

## Memory Budget on 2 GB EC2 (3 Apps)

```
2,048 MB total
├── Ubuntu OS:                ~150 MB
├── Redis process × 3:        ~150 MB  (50 MB idle per process)
├── Connection overhead:       ~50 MB  (500 clients × 3 × ~30 bytes avg)
│
├── App1 maxmemory:            450 MB
├── App2 maxmemory:            450 MB
└── App3 maxmemory:            450 MB
                           ─────────
                             1,700 MB  ← leaves 348 MB headroom ✅
```

### Uneven Traffic — Tune Per App

```ini
# App1 is high-traffic (main user-facing app)
maxmemory 800mb

# App2 is medium (admin panel)
maxmemory 350mb

# App3 is low (background tool)
maxmemory 150mb

# Total: 1,300 MB + 350 MB overhead = 1,650 MB ✅ (leaves 400 MB free)
```

### What Each App Gets at 450 MB

| Data type | RAM per item | Capacity at 450 MB |
|---|---|---|
| Sessions | ~3 KB | ~150,000 active sessions |
| Cache entries (small) | ~1 KB | ~450,000 entries |
| Cache entries (medium 10 KB) | ~10 KB | ~45,000 entries |
| Rate limiter counters | ~100 bytes | ~4,500,000 counters |
| Horizon queue jobs | ~5 KB | ~90,000 queued jobs |

---

## Monitoring All Instances

### Quick Status Check

```bash
for port in 6379 6380 6381; do
  app="App$((port - 6378))"
  pass="App$((port - 6378))\$trongRedisPass!"
  echo "=== $app (port $port) ==="
  redis-cli -h 10.0.1.50 -p $port -a "$pass" INFO server | grep uptime_in_days
  redis-cli -h 10.0.1.50 -p $port -a "$pass" INFO memory | grep used_memory_human
  redis-cli -h 10.0.1.50 -p $port -a "$pass" INFO clients | grep connected_clients
  redis-cli -h 10.0.1.50 -p $port -a "$pass" INFO keyspace
  echo ""
done
```

### Watch Memory Live

```bash
watch -n 3 '
echo "PORT  | USED MEM | CLIENTS | KEYS"
echo "------|----------|---------|-----"
for port in 6379 6380 6381; do
  mem=$(redis-cli -p $port -a "${PASS}" INFO memory 2>/dev/null | grep used_memory_human | cut -d: -f2 | tr -d "\r")
  clients=$(redis-cli -p $port -a "${PASS}" INFO clients 2>/dev/null | grep connected_clients | cut -d: -f2 | tr -d "\r")
  keys=$(redis-cli -p $port -a "${PASS}" DBSIZE 2>/dev/null)
  printf "%-6s| %-9s| %-8s| %s\n" "$port" "$mem" "$clients" "$keys"
done
'
```

### Log Locations

```bash
tail -f /var/log/redis/app1.log    # App1 Redis events
tail -f /var/log/redis/app2.log    # App2 Redis events
tail -f /var/log/redis/app3.log    # App3 Redis events
```

---

## Adding a New App Later

```bash
# 1. Create config
sudo cp /etc/redis/app1.conf /etc/redis/app4.conf
sudo sed -i 's/6379/6382/g'               /etc/redis/app4.conf
sudo sed -i 's/app1/app4/g'               /etc/redis/app4.conf
sudo sed -i 's/App1\$trongRedisPass!/App4$trongRedisPass!/g' /etc/redis/app4.conf

# 2. Create data dir
sudo mkdir -p /var/lib/redis/app4
sudo chown redis:redis /var/lib/redis/app4

# 3. Create systemd service
sudo cp /etc/systemd/system/redis-app1.service \
        /etc/systemd/system/redis-app4.service
sudo sed -i 's/app1/app4/g; s/6379/6382/g; s/App1/App4/g' \
        /etc/systemd/system/redis-app4.service

# 4. Start
sudo systemctl daemon-reload
sudo systemctl enable redis-app4
sudo systemctl start  redis-app4

# 5. Add firewall rule
sudo ufw allow from 10.0.40.0/24 to any port 6382 comment "App4 Redis"
```

---

## Summary

| Question | Answer |
|---|---|
| Can App 1 accidentally connect to App 2? | ❌ Impossible — different port AND different password |
| Can a developer copy the wrong `.env`? | Connection refused immediately — hard error |
| Do apps need different DB numbers? | No — all apps use DB 0, 1, 2 cleanly |
| What if one app's Redis needs a restart? | Only that app is affected — others keep running |
| What if one app leaks memory / hits maxmemory? | Only that app is throttled — others unaffected |
| How many apps on 2 GB EC2? | **3 comfortably** at 450 MB each; or 4–5 with smaller budgets |
| How to add a new app? | Copy conf + systemd + add firewall rule |

---

*Last updated: May 12, 2026*

