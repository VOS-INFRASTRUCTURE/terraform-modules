# Redis Metrics & Telemetry (Stage 2 Monitoring)

Once an instance is confirmed live and reachable, the next stage of monitoring is analyzing its performance, memory limits, keyspace health, and connection scaling.

To retrieve these metrics from an app's Redis instance, run:
```bash
export REDISCLI_AUTH="your_password"
redis-cli -p <port> INFO <section>
unset REDISCLI_AUTH
```

---

## 1. Memory Usage vs Limit
Redis stores all data in memory, making memory monitoring critical.

```bash
export REDISCLI_AUTH="your_password"
redis-cli -p 6379 INFO memory | grep -E \
  "used_memory_human|used_memory_rss_human|maxmemory_human|mem_fragmentation_ratio|maxmemory_policy"
unset REDISCLI_AUTH
```

### Metrics Explained
* **`used_memory_human`**: The total number of bytes allocated by Redis using its allocator (actual dataset size).
* **`used_memory_rss_human`**: The number of bytes that the operating system reports Redis has allocated (Resident Set Size). This includes memory fragmentation.
* **`maxmemory_human`**: The hard ceiling configured for this Redis instance.
* **`mem_fragmentation_ratio`**: Ratio of `used_memory_rss` to `used_memory`. 
  * **Healthy (1.0 - 1.5)**: Normal allocator overhead.
  * **High (> 1.5)**: High memory fragmentation (wasted OS memory). Can be resolved via active defragmentation.
  * **Low (< 1.0)**: The physical memory is thrashing / swapping to disk. **Critical performance degradation is occurring.**
* **`maxmemory_policy`**: The eviction policy chosen for this instance.

---

## 2. Eviction Count
Eviction occurs when Redis hits its `maxmemory` limit and must remove keys to make room for new write commands.

```bash
redis-cli -p 6379 INFO stats | grep evicted_keys
# evicted_keys:42318
```

### How to Interpret Eviction Counts
* **`evicted_keys = 0`**: Memory usage is safe within the config limits.
* **`evicted_keys > 0` with `allkeys-lru`**: Healthy and expected behaviour if Redis is used purely as a cache. Old cache keys are naturally pruned.
* **`evicted_keys > 0` with `volatile-lru`**: Potentially dangerous. If Redis holds active sessions or user data with TTLs, they are being evicted prematurely, logging out users.
* **`evicted_keys > 0` with `noeviction`**: Impossible. Eviction is disabled; instead, write commands will fail with OOM errors.

---

## 3. Cache Hit Rate
The cache hit rate indicates what percentage of read requests are being successfully served from Redis memory rather than missing and falling back to a database.

```bash
redis-cli -p 6379 INFO stats | grep -E "keyspace_hits|keyspace_misses"
# keyspace_hits:   2847392
# keyspace_misses: 103847
```

$$\text{Cache Hit Rate} = \frac{\text{keyspace\_hits}}{\text{keyspace\_hits} + \text{keyspace\_misses}} \times 100$$

* **Hit rate > 90%**: Excellent. Cache strategy is highly effective.
* **Hit rate 70% - 90%**: Normal.
* **Hit rate < 70%**: Poor. The cache is either too small (causing frequent evictions of useful keys), or keys are expiring too quickly.

---

## 4. Key Count & Database Expirations
Checking key distributions per database helps identify memory leaks.

```bash
redis-cli -p 6379 INFO keyspace
# db1:keys=89432,expires=89432,avg_ttl=86400000
# db2:keys=12847,expires=2000,avg_ttl=7200000
```

* **`keys`**: Total number of keys in the database.
* **`expires`**: Total number of keys that have an explicit TTL expiration set.
* **The Red Flag**: If `keys` is significantly larger than `expires` (e.g. database has 10,000 keys but only 2,000 expires), then **8,000 keys have no expiration date**. If the eviction policy is `volatile-*`, these 8,000 keys will live in memory forever, creating a memory leak.

---

## 5. Connected Clients
Monitor client connections to prevent resource exhaustion.

```bash
redis-cli -p 6379 INFO clients | grep connected_clients
# connected_clients:47
```

If connected clients spike unexpectedly:
1. **ECS scaled out** heavily, creating more application workers.
2. **Connection Leaking** is occurring in your application pool (connections are opened but never closed).
3. Redis has a default limit of `maxclients 10000`.

---

## 6. Slow Commands (SLOWLOG)
Redis is single-threaded. If a complex command runs slowly, it blocks all other requests behind it.

```bash
# Get the last 10 commands that took longer than configured thresholds
redis-cli -p 6379 SLOWLOG GET 10
```

### Configuration in `redis.conf`:
```ini
# Log commands that take longer than 1000 microseconds (1 millisecond)
slowlog-log-slower-than 1000

# Keep the last 128 slow commands in memory
slowlog-max-len 128
```
Common slow commands to avoid in production:
* `KEYS *` (Use `SCAN` instead)
* `FLUSHALL` or `FLUSHDB` synchronously
* Processing very large sets/hashes (`SMEMBERS`, `HGETALL` with millions of fields)
