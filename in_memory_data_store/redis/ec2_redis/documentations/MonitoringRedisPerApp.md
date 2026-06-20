# Redis Per-App Monitoring — Memory Usage, Exhaustion & Alerting

## The Core Question: How Do You Know Which App Is Using Memory Well?

Each app has its own Redis process on a separate port with its own `maxmemory`.
You monitor them independently — each gives you its own isolated metrics.

```
redis-cli -p 6379 INFO memory   → App1 memory stats
redis-cli -p 6380 INFO memory   → App2 memory stats
redis-cli -p 6381 INFO memory   → App3 memory stats
redis-cli -p 6382 INFO memory   → App4 memory stats
```

---

## What Happens When an App Exhausts Its `maxmemory`?

This is controlled entirely by `maxmemory-policy` in each app's `redis.conf`.

### The 8 Policies and Their Behaviour

| Policy | What happens when full | Best for |
|---|---|---|
| `allkeys-lru` | Evicts the **least recently used** key across all keys | Cache — you want old data removed automatically |
| `volatile-lru` | Evicts least recently used key **that has a TTL set** | Sessions + cache mixed — sessions survive if they have no TTL |
| `allkeys-lfu` | Evicts the **least frequently used** key | Cache with hot/cold data patterns |
| `volatile-lfu` | Evicts least frequently used key with TTL | Mixed workloads |
| `allkeys-random` | Evicts a **random** key | Rare — only if you don't care which data survives |
| `volatile-random` | Evicts a random key with TTL | Rare |
| `volatile-ttl` | Evicts the key with the **shortest TTL** | When you want soonest-to-expire data removed first |
| `noeviction` | **Rejects all write commands** — returns error | Queues/jobs — you must never lose data |

### Behaviour Diagram

```
App hits maxmemory
       ↓
maxmemory-policy = allkeys-lru?
  ├── YES → silently evict old cache keys → writes continue ✅
  └── NO (noeviction) → return OOM error to Laravel ❌
              ↓
       Laravel throws:
       "Predis\Response\ServerException: OOM command not allowed
        when used memory > 'maxmemory'"
              ↓
       Cache::put() fails → exception in your app
       Session writes fail → user session lost
```

### Recommended Policy Per Use Case

```ini
# App using Redis for CACHE only
maxmemory-policy allkeys-lru     # ← old cache auto-evicted, no errors

# App using Redis for SESSIONS only
maxmemory-policy volatile-lru    # ← only evict keys with TTL (sessions have TTL)
                                 #   permanent keys (locks) are safe

# App using Redis for QUEUES (Horizon)
maxmemory-policy noeviction      # ← never silently drop a job — fail loudly instead

# App using Redis for CACHE + SESSIONS (most Laravel apps)
maxmemory-policy volatile-lru    # ← safe: sessions have TTL, cache has TTL
                                 #   only data with TTL gets evicted
```

---

## Key Metrics to Monitor Per App

### 1. Memory Usage vs Limit

```bash
redis-cli -p 6379 -a 'App1Pass' INFO memory | grep -E \
  "used_memory_human|used_memory_rss_human|maxmemory_human|mem_fragmentation_ratio|maxmemory_policy"
```

Sample output:
```
used_memory_human:       1.21G    ← actual data in use
used_memory_rss_human:   1.45G    ← OS-allocated (includes fragmentation)
maxmemory_human:         1.70G    ← your limit
mem_fragmentation_ratio: 1.20     ← RSS/used — healthy is 1.0–1.5
maxmemory_policy:        volatile-lru
```

**Usage %** = `used_memory / maxmemory × 100`
```
1.21 GB / 1.70 GB = 71% used  ← getting close, worth watching
```

### 2. Eviction Count — Is Data Being Silently Dropped?

```bash
redis-cli -p 6379 -a 'App1Pass' INFO stats | grep evicted_keys
# evicted_keys:42318   ← 42,318 keys have been evicted since startup
```

- `evicted_keys = 0` → memory is fine, nothing ever evicted
- `evicted_keys > 0` with `allkeys-lru` → normal cache eviction behaviour ✅
- `evicted_keys > 0` with `volatile-lru` → sessions may be getting evicted ⚠️
- Rising rapidly → app is generating data faster than TTLs expire → **increase maxmemory**

### 3. Hit Rate — Is the Cache Actually Working?

```bash
redis-cli -p 6379 -a 'App1Pass' INFO stats | grep -E "keyspace_hits|keyspace_misses"
# keyspace_hits:   2847392
# keyspace_misses: 103847
```

**Hit rate** = `hits / (hits + misses) × 100`
```
2,847,392 / (2,847,392 + 103,847) = 96.5% hit rate  ← excellent ✅
```

- **> 90%** → cache is very effective
- **70–90%** → acceptable
- **< 70%** → cache is being evicted too aggressively → increase maxmemory or review TTLs

### 4. Key Count Per Database

```bash
redis-cli -p 6379 -a 'App1Pass' INFO keyspace
# db0:keys=3421,expires=2100,avg_ttl=3600000    ← default/queues
# db1:keys=89432,expires=89432,avg_ttl=86400000 ← cache (all have TTL) ✅
# db2:keys=12847,expires=12847,avg_ttl=7200000  ← sessions (all have TTL) ✅
```

- `keys` = `expires` → all keys have TTL → eviction policy is working correctly
- `keys` > `expires` → some keys have **no TTL** → those can never be evicted → memory leak risk

### 5. Connected Clients

```bash
redis-cli -p 6379 -a 'App1Pass' INFO clients | grep connected_clients
# connected_clients:47
```

Each PHP-FPM worker holds a connection while processing a request.
If this spikes unexpectedly → ECS scaled out a lot, or connections are leaking.

### 6. Slow Commands

```bash
redis-cli -p 6379 -a 'App1Pass' SLOWLOG GET 10
# Returns last 10 commands that took > slowlog-log-slower-than microseconds
```

Add to `redis.conf`:
```ini
slowlog-log-slower-than 1000   # log commands taking > 1ms
slowlog-max-len 128             # keep last 128 slow commands
```

---

## Live Dashboard — Watch All Apps at Once

### Memory Overview (all 4 apps)

```bash
watch -n 5 '
printf "%-6s %-8s %-8s %-8s %-8s %-10s %-12s\n" \
  "PORT" "USED" "MAX" "USED%" "FRAG" "EVICTED" "HIT_RATE"
echo "────────────────────────────────────────────────────────────────"
for port in 6379 6380 6381 6382; do
  pass=$(cat /etc/redis/passwords/port-${port})
  used=$(redis-cli -p $port -a "$pass" INFO memory 2>/dev/null | grep "^used_memory:" | cut -d: -f2 | tr -d "\r")
  max=$(redis-cli -p $port -a "$pass" INFO memory 2>/dev/null | grep "^maxmemory:" | cut -d: -f2 | tr -d "\r")
  frag=$(redis-cli -p $port -a "$pass" INFO memory 2>/dev/null | grep "mem_fragmentation_ratio" | cut -d: -f2 | tr -d "\r")
  evicted=$(redis-cli -p $port -a "$pass" INFO stats 2>/dev/null | grep evicted_keys | cut -d: -f2 | tr -d "\r")
  hits=$(redis-cli -p $port -a "$pass" INFO stats 2>/dev/null | grep keyspace_hits | cut -d: -f2 | tr -d "\r")
  misses=$(redis-cli -p $port -a "$pass" INFO stats 2>/dev/null | grep keyspace_misses | cut -d: -f2 | tr -d "\r")

  used_mb=$((used / 1024 / 1024))
  max_mb=$((max / 1024 / 1024))
  pct=0; [ "$max_mb" -gt 0 ] && pct=$((used_mb * 100 / max_mb))
  total=$((hits + misses)); rate=0
  [ "$total" -gt 0 ] && rate=$((hits * 100 / total))

  printf "%-6s %-8s %-8s %-8s %-8s %-10s %-12s\n" \
    "$port" "${used_mb}MB" "${max_mb}MB" "${pct}%" "$frag" "$evicted" "${rate}%"
done
'
```

Sample output:
```
PORT   USED     MAX      USED%    FRAG     EVICTED    HIT_RATE
────────────────────────────────────────────────────────────────
6379   823MB    1700MB   48%      1.15     0          97%
6380   1421MB   1700MB   84%      1.32     12847      91%       ← getting full
6381   234MB    1700MB   14%      1.08     0          99%
6382   1698MB   1700MB   99%      1.89     204832     67%       ← 🚨 nearly full
```

---

## Alerting — Get Notified Before Memory Runs Out

### Option 1: CloudWatch Agent (push Redis metrics to CloudWatch)

Install the CloudWatch agent on the EC2 and configure it to run a custom script:

```bash
sudo apt install -y amazon-cloudwatch-agent
```

Create `/opt/redis-metrics/push-metrics.sh`:

```bash
#!/bin/bash
# Push Redis memory metrics to CloudWatch for all app instances

REGION="us-east-1"
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

declare -A PORTS=(
  [6379]="app1"
  [6380]="app2"
  [6381]="app3"
  [6382]="app4"
)

declare -A PASSWORDS=(
  [6379]="App1\$trongRedisPass!"
  [6380]="App2\$trongRedisPass!"
  [6381]="App3\$trongRedisPass!"
  [6382]="App4\$trongRedisPass!"
)

for port in "${!PORTS[@]}"; do
  app="${PORTS[$port]}"
  pass="${PASSWORDS[$port]}"

  used=$(redis-cli -p $port -a "$pass" INFO memory 2>/dev/null \
    | grep "^used_memory:" | cut -d: -f2 | tr -d '\r ')
  max=$(redis-cli -p $port -a "$pass" INFO memory 2>/dev/null \
    | grep "^maxmemory:" | cut -d: -f2 | tr -d '\r ')
  evicted=$(redis-cli -p $port -a "$pass" INFO stats 2>/dev/null \
    | grep "evicted_keys:" | cut -d: -f2 | tr -d '\r ')
  hits=$(redis-cli -p $port -a "$pass" INFO stats 2>/dev/null \
    | grep "keyspace_hits:" | cut -d: -f2 | tr -d '\r ')
  misses=$(redis-cli -p $port -a "$pass" INFO stats 2>/dev/null \
    | grep "keyspace_misses:" | cut -d: -f2 | tr -d '\r ')

  # Memory usage %
  pct=0
  [ "${max:-0}" -gt 0 ] && pct=$((used * 100 / max))

  # Push to CloudWatch
  aws cloudwatch put-metric-data \
    --region "$REGION" \
    --namespace "Redis/PerApp" \
    --metric-data \
      "[
        {\"MetricName\":\"MemoryUsedPercent\",
         \"Dimensions\":[{\"Name\":\"App\",\"Value\":\"$app\"}],
         \"Value\":$pct,\"Unit\":\"Percent\"},
        {\"MetricName\":\"EvictedKeys\",
         \"Dimensions\":[{\"Name\":\"App\",\"Value\":\"$app\"}],
         \"Value\":${evicted:-0},\"Unit\":\"Count\"},
        {\"MetricName\":\"MemoryUsedBytes\",
         \"Dimensions\":[{\"Name\":\"App\",\"Value\":\"$app\"}],
         \"Value\":${used:-0},\"Unit\":\"Bytes\"}
      ]"
done
```

```bash
chmod +x /opt/redis-metrics/push-metrics.sh

# Run every 60 seconds via cron
echo "* * * * * root /opt/redis-metrics/push-metrics.sh >> /var/log/redis-metrics.log 2>&1" \
  | sudo tee /etc/cron.d/redis-metrics
```

### Option 2: CloudWatch Alarms on the Custom Metrics

```bash
# Alert when App2 memory > 80%
aws cloudwatch put-metric-alarm \
  --alarm-name "redis-app2-memory-high" \
  --alarm-description "App2 Redis memory above 80%" \
  --metric-name "MemoryUsedPercent" \
  --namespace "Redis/PerApp" \
  --dimensions Name=App,Value=app2 \
  --statistic Average \
  --period 60 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 3 \
  --alarm-actions "arn:aws:sns:us-east-1:123456789012:redis-alerts"

# Alert when any app has evictions increasing rapidly (> 1000 in 1 minute)
aws cloudwatch put-metric-alarm \
  --alarm-name "redis-app2-evictions-high" \
  --alarm-description "App2 Redis evicting too many keys" \
  --metric-name "EvictedKeys" \
  --namespace "Redis/PerApp" \
  --dimensions Name=App,Value=app2 \
  --statistic Sum \
  --period 60 \
  --threshold 1000 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions "arn:aws:sns:us-east-1:123456789012:redis-alerts"
```

### Option 3: Simple Bash Alert via Email/Slack (no CloudWatch)

```bash
#!/bin/bash
# /opt/redis-metrics/alert-check.sh
# Run via cron every 5 minutes

SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
THRESHOLD=85   # alert at 85% memory usage

declare -A PORTS=([6379]="app1" [6380]="app2" [6381]="app3" [6382]="app4")
declare -A PASSWORDS=(
  [6379]="App1\$trongRedisPass!"
  [6380]="App2\$trongRedisPass!"
  [6381]="App3\$trongRedisPass!"
  [6382]="App4\$trongRedisPass!"
)

for port in "${!PORTS[@]}"; do
  app="${PORTS[$port]}"
  pass="${PASSWORDS[$port]}"

  used=$(redis-cli -p $port -a "$pass" INFO memory 2>/dev/null \
    | grep "^used_memory:" | cut -d: -f2 | tr -d '\r ')
  max=$(redis-cli -p $port -a "$pass" INFO memory 2>/dev/null \
    | grep "^maxmemory:" | cut -d: -f2 | tr -d '\r ')

  [ "${max:-0}" -eq 0 ] && continue
  pct=$((used * 100 / max))

  if [ "$pct" -ge "$THRESHOLD" ]; then
    curl -s -X POST "$SLACK_WEBHOOK" \
      -H 'Content-type: application/json' \
      --data "{\"text\":\"🚨 *Redis Alert* — *${app}* (port ${port}) memory at *${pct}%* of maxmemory. Consider increasing maxmemory in /etc/redis/${app}.conf\"}"
  fi
done
```

```bash
chmod +x /opt/redis-metrics/alert-check.sh
echo "*/5 * * * * root /opt/redis-metrics/alert-check.sh" \
  | sudo tee /etc/cron.d/redis-alert-check
```

---

## What To Do When an App Is Running Out of Memory

### Step 1: Diagnose — Why Is Memory Full?

```bash
# Check key counts and TTLs
redis-cli -p 6380 -a 'App2Pass' INFO keyspace
# db0:keys=142000,expires=0,avg_ttl=0   ← 142,000 keys with NO TTL 💥
# db1:keys=89000,expires=89000,avg_ttl=3600000

# Keys without TTL never expire and never get evicted (with volatile-lru)
# → find what's creating permanent keys

# Sample the keyspace to see what types are growing
redis-cli -p 6380 -a 'App2Pass' --scan --pattern "*" | head -20
redis-cli -p 6380 -a 'App2Pass' RANDOMKEY
redis-cli -p 6380 -a 'App2Pass' TYPE <key>
```

### Step 2: Check if Laravel is Setting TTLs Correctly

```php
// ❌ Bad — no TTL, key lives forever
Cache::forever('report:2024', $data);

// ✅ Good — TTL set, will expire and be evicted if needed
Cache::put('report:2024', $data, now()->addHours(24));

// ❌ Bad — using Redis::set() directly without TTL
Redis::set('my:key', $value);

// ✅ Good — always set expiry on direct Redis calls
Redis::set('my:key', $value);
Redis::expire('my:key', 3600);
// or
Redis::setex('my:key', 3600, $value);
```

### Step 3: Increase maxmemory (Zero Downtime)

You can increase `maxmemory` **while Redis is running** — no restart needed:

```bash
# Increase App2's maxmemory from 1700MB to 2200MB live
redis-cli -p 6380 -a 'App2$trongRedisPass!' CONFIG SET maxmemory 2306867200
# 2306867200 bytes = 2,200 MB

# Verify
redis-cli -p 6380 -a 'App2$trongRedisPass!' CONFIG GET maxmemory
# maxmemory  2306867200  ✅
```

Then update the config file so it persists after restart:

```bash
sudo sed -i 's/^maxmemory 1700mb/maxmemory 2200mb/' /etc/redis/app2.conf
```

> ⚠️ Make sure the new `maxmemory` value fits within the total EC2 RAM.
> Recalculate: sum of all apps' maxmemory + OS overhead must stay ≤ total EC2 RAM.

```bash
# Quick check: total allocated vs available
echo "App1: $(redis-cli -p 6379 -a 'p1' CONFIG GET maxmemory | tail -1) bytes"
echo "App2: $(redis-cli -p 6380 -a 'p2' CONFIG GET maxmemory | tail -1) bytes"
echo "App3: $(redis-cli -p 6381 -a 'p3' CONFIG GET maxmemory | tail -1) bytes"
echo "App4: $(redis-cli -p 6382 -a 'p4' CONFIG GET maxmemory | tail -1) bytes"
free -m   # check remaining OS RAM
```

### Step 4: Evict Unnecessary Data Manually

```bash
# Find and delete keys matching a pattern
redis-cli -p 6380 -a 'App2Pass' --scan --pattern "laravel_cache:reports:*" \
  | xargs redis-cli -p 6380 -a 'App2Pass' DEL

# Delete all cache keys (DB 1 only) — sessions and queues unaffected
redis-cli -p 6380 -a 'App2Pass' -n 1 FLUSHDB
# Note: only works if FLUSHDB is not disabled in rename-command
```

### Step 5: If Memory Is Truly Insufficient — Upgrade the Instance

```
r6g.medium (8 GB)  →  resize to  r6g.large (16 GB)
  ↓ cost: $37/mo   →              $74/mo
  ↓ per-app RAM: 1.7 GB  →       3.5 GB per app (for 4 apps)

Resize steps:
1. Stop Redis gracefully (BGSAVE first)
   redis-cli -p 6379 BGSAVE && wait
   sudo systemctl stop redis-app1 redis-app2 redis-app3 redis-app4

2. Stop EC2 instance
   aws ec2 stop-instances --instance-ids i-xxxxxxxxxxxxxxxxx

3. Change instance type
   aws ec2 modify-instance-attribute \
     --instance-id i-xxxxxxxxxxxxxxxxx \
     --instance-type r6g.large

4. Start instance
   aws ec2 start-instances --instance-ids i-xxxxxxxxxxxxxxxxx

5. Update maxmemory in each redis.conf and restart services
```

---

## Alert Thresholds Reference

| Metric | Warning | Critical | Action |
|---|---|---|---|
| Memory used % | > 75% | > 90% | Review TTLs, increase maxmemory |
| Evicted keys (allkeys-lru) | > 500/min | > 5000/min | Normal for cache, but watch hit rate |
| Evicted keys (volatile-lru) | > 100/min | > 1000/min | Sessions at risk — increase maxmemory immediately |
| Evicted keys (noeviction) | N/A — errors instead | OOM errors returned | Increase maxmemory or clear stale data |
| Cache hit rate | < 80% | < 60% | Evictions too aggressive — increase maxmemory |
| Fragmentation ratio | > 1.5 | > 2.0 | Restart Redis during low traffic to defragment |
| Connected clients | > 400/instance | > 450/instance | Check ECS scaling, look for connection leaks |
| Keys without TTL in cache DB | Any growth | Rapid growth | Laravel code bug — all cache writes must have TTL |

---

## Summary

| Question | Answer |
|---|---|
| How do I know which app uses memory well? | `INFO memory` per port — compare `used_memory` vs `maxmemory` |
| What if an app hits maxmemory? | Depends on policy: `allkeys-lru` evicts old data silently; `noeviction` rejects writes with error |
| How do I detect silent cache evictions? | `INFO stats → evicted_keys` rising + `keyspace_hits/misses` hit rate dropping |
| Can I increase maxmemory without restart? | ✅ Yes — `CONFIG SET maxmemory <bytes>` takes effect immediately |
| What causes memory to fill up unexpectedly? | Keys without TTL — `db0:keys=N,expires=0` in `INFO keyspace` is the red flag |
| Best policy for cache+sessions? | `volatile-lru` — only evicts keys that have TTL set |
| Best policy for queues? | `noeviction` — never silently drop a job, fail loudly |

---

*Last updated: May 12, 2026*

