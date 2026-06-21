# Redis Memory Remediation & Triage (Stage 4)

When memory alarms fire or write commands start throwing Out Of Memory (OOM) errors, use this playbook to restore cluster health.

---

## 1. Diagnose Memory Allocations

Identify what databases, key prefixes, and namespaces are using the most memory.

### Step A: Identify databases without TTL
```bash
redis-cli -p 6380 -a "myPass" INFO keyspace
# db0:keys=142000,expires=0,avg_ttl=0   ← CRITICAL: 142,000 keys with NO TTL
```
Keys without TTL never expire and are immune to `volatile-lru` evictions, leading to leaks.

### Step B: Sample keys to identify patterns
```bash
# Scan keyspace for key prefixes
redis-cli -p 6380 -a "myPass" --scan --pattern "*" | head -30

# Retrieve a random key to see its structure
redis-cli -p 6380 -a "myPass" RANDOMKEY

# Check the type of the key (string, hash, list, set, zset)
redis-cli -p 6380 -a "myPass" TYPE "laravel_cache:reports:2024"
```

---

## 2. Check Laravel Codebase Configuration

Laravel applications are the primary source of Redis keys. Make sure your application codebase uses expiration TTLs.

```php
// ❌ BAD - Writes key with no expiration. Survives volatile-lru forever.
Cache::forever('report_data', $largeJsonString);
Redis::set('last_login', $timestamp);

// ✅ GOOD - Explicitly set an expiration window
Cache::put('report_data', $largeJsonString, now()->addHours(12));
Redis::setex('last_login', 3600, $timestamp); // Expirations in seconds
```

---

## 3. Live Runtime Adjustment of `maxmemory` (Zero Downtime)

If your EC2 instance has free RAM, you can increase a Redis instance's `maxmemory` limit **immediately** without restarting the process.

### Step A: Update the running configuration
```bash
# Increase port 6380's maxmemory limit to 2.2 GB (value must be in bytes)
redis-cli -p 6380 -a "myPass" CONFIG SET maxmemory 2362232012

# Verify that the changes took effect
redis-cli -p 6380 -a "myPass" CONFIG GET maxmemory
# maxmemory
# 2362232012
```

### Step B: Persist the change to the config file
If the service restarts, changes made via `CONFIG SET` will be lost unless you edit the config file:
```bash
# Update the configuration file so changes survive restarts
sudo sed -i 's/^maxmemory .*/maxmemory 2200mb/' /etc/redis/app2.conf
```

> [!WARNING]
> Sum the `maxmemory` settings of all active Redis instances on the host plus 2 GB for OS/system overhead. Ensure this total does not exceed the physical RAM of the host.

---

## 4. Manual Evictions & Cleansing

If you need to free up memory immediately and cannot increase `maxmemory`:

### Delete keys matching a pattern:
```bash
redis-cli -p 6380 -a "myPass" --scan --pattern "laravel_cache:temp:*" \
  | xargs -R 100 redis-cli -p 6380 -a "myPass" DEL
```

### Flush a single database (e.g. Cache DB):
```bash
# Deletes keys inside database 1 only; database 0 (queues) is unaffected
redis-cli -p 6380 -a "myPass" -n 1 FLUSHDB
```

---

## 5. Upgrade the EC2 Instance Type

If the host runs out of RAM, you must scale up the EC2 instance (e.g. from `r6g.medium` with 8 GB RAM to `r6g.large` with 16 GB RAM).

### Triage / Upsize Checklist:
1. **Force persistence write (BGSAVE)** to avoid data loss on shutdown:
   ```bash
   redis-cli -p 6379 -a "pass" BGSAVE
   # Wait for output from background write to complete
   ```
2. **Stop the services gracefully**:
   ```bash
   sudo systemctl stop redis-app1 redis-app2 redis-app3 redis-app4
   ```
3. **Stop the EC2 Instance**:
   ```bash
   aws ec2 stop-instances --instance-ids i-xxxxxxxxxxxxxxxxx
   ```
4. **Modify the Instance Type**:
   ```bash
   aws ec2 modify-instance-attribute \
     --instance-id i-xxxxxxxxxxxxxxxxx \
     --instance-type r6g.large
   ```
5. **Start the Instance**:
   ```bash
   aws ec2 start-instances --instance-ids i-xxxxxxxxxxxxxxxxx
   ```
6. Update individual config allocations (`/etc/redis/*.conf`) to leverage the new RAM, then restart:
   ```bash
   sudo systemctl start redis-app1 redis-app2 redis-app3 redis-app4
   ```
