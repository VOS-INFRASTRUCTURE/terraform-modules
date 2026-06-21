# Redis Liveness Testing (Stage 1 Monitoring)

Before gathering telemetry metrics (like memory usage, client counts, or hit rates), you must establish whether the Redis instances are actually alive, accepting connections, and processing commands.

If a Redis instance is hung (due to memory exhaustion, thread blockage, or OS issues), high-level telemetry commands might block or fail. Standardizing on a fast, non-blocking liveness check prevents false metrics and ensures early detection of server outages.

---

## 1. TCP Port Reachability Check

The first step in checking if Redis is alive is to verify that its TCP port is open and listening. This does not execute any Redis commands, making it extremely lightweight.

### Option A: Using `nc` (Netcat)
```bash
# Check if port 6379 is open with a 3-second timeout
nc -z -w 3 127.0.0.1 6379
```
* **Exit code `0`**: Port is open and listening.
* **Exit code `1` (or non-zero)**: Connection refused or timed out.

### Option B: Using Native Bash Sockets (No dependencies)
If `nc` is not installed on the system, you can use Bash's built-in socket handler:
```bash
(timeout 3 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/6379") 2>/dev/null
```
* **Exit code `0`**: Connection succeeded.
* **Non-zero exit code**: Connection failed.

---

## 2. Redis PING Command Check

Once the TCP port is confirmed open, you must verify that the Redis server engine is actually processing commands. This is done by sending the `PING` command, which should return `PONG`.

### Passing Passwords Safely
> [!CAUTION]
> Never pass passwords using the `-a` argument directly in cron scripts or daemon configurations (e.g. `redis-cli -a "myPass" PING`). Doing so exposes the password in the system's process table (`ps aux`), allowing any unprivileged user on the machine to see it.

Instead, export the password to the `REDISCLI_AUTH` environment variable:

```bash
export REDISCLI_AUTH="your_redis_password"
response=$(redis-cli -h 127.0.0.1 -p 6379 PING 2>/dev/null)
unset REDISCLI_AUTH

if [ "$response" = "PONG" ]; then
  echo "Redis is responsive!"
else
  echo "Redis failed to respond to PONG (Got: $response)"
  exit 3
fi
```

---

## 3. Systemd Service Check

If you are running Redis as systemd services on an EC2 instance, you can query systemd directly to check if the unit is loaded and active.

```bash
systemctl is-active redis-app1
```
* **Output `active` (Exit code `0`)**: Service is running.
* **Output `inactive` or `failed` (Non-zero exit code)**: Service is stopped or crashed.

---

## 4. Automated Liveness Utility Script

To combine all of the above checks into a single command, use the provided health check script located in this folder: [`redis-health-check.sh`](file:///c:/Repos/VOS/terraform-apps/terraform-modules/in_memory_data_store/redis/ec2_redis/documentations/monitoring/redis-health-check.sh).

### Basic Liveness Checks
```bash
# Check default instance on 6379
./redis-health-check.sh

# Check instance on 6380 with password file
./redis-health-check.sh -p 6380 -f /etc/redis/passwords/port-6380

# Check port, service name, and systemd state
./redis-health-check.sh -p 6380 -f /etc/redis/passwords/port-6380 -s redis-app2
```

### Script Exit Code Reference
When automating checks in cron jobs or load balancer targets, use the script's exit codes to route alerts:
* **`0`**: Healthy & responsive.
* **`2`**: Port unreachable (TCP Socket Connection Failed).
* **`3`**: Redis failed to respond with PONG (Unresponsive engine or incorrect auth credentials).
* **`4`**: Systemd service registered but not active.
