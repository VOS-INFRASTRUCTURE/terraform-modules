# Redis Insight — Docker Setup

Run Redis Insight as a Docker container alongside your Redis instances. The UI is
served in your browser at `http://localhost:5540`. No desktop app install needed.

This guide covers:
- [Quick single-container run](#1-quick-run-no-compose)
- [Docker Compose with Redis + Redis Insight](#2-docker-compose-local-dev-stack)
- [Connecting Redis Insight to your instances](#3-adding-databases-in-the-ui)

For adding Nginx auth on top of this setup, see [03_nginx_proxy](../03_nginx_proxy/README.md).

---

## Flow (local dev stack)

```
  Your Browser
       │
       │  http://localhost:5540
       ▼
  ┌─────────────────────────────────────────────────────┐
  │  Docker Network: redis-net                          │
  │                                                     │
  │  ┌─────────────────┐                               │
  │  │  Redis Insight  │  ← port 5540 exposed to host  │
  │  │  :5540          │                               │
  │  └────────┬────────┘                               │
  │           │  TCP (internal Docker network)          │
  │    ┌──────┴──────┐                                 │
  │    ▼             ▼                                  │
  │  ┌──────────┐  ┌──────────┐                        │
  │  │  redis-  │  │  redis-  │                        │
  │  │  app1    │  │  app2    │  ...                   │
  │  │  :6379   │  │  :6380   │                        │
  │  └──────────┘  └──────────┘                        │
  └─────────────────────────────────────────────────────┘
```

Inside Docker, Redis Insight reaches Redis instances by **container name** (Docker DNS),
not by `localhost`. This is the key difference from the direct install approach.

---

## 1. Quick Run (No Compose)

If you just want Redis Insight running against an already-running Redis:

```bash
docker run -d \
  --name redis-insight \
  -p 5540:5540 \
  -v redis-insight-data:/data \
  redis/redisinsight:latest
```

Open `http://localhost:5540` in your browser.

To connect to a Redis container on the same Docker host, pass the container's IP or
use `host.docker.internal` to reach the host network:

```
Host:     host.docker.internal
Port:     6379
Password: <your password>
```

---

## 2. Docker Compose — Local Dev Stack

Use this when Redis Insight and your Redis instances all run in Docker together.

**`docker-compose.yml`**

```yaml
services:

  redis-app1:
    image: redis:8.0-alpine
    container_name: redis-app1
    restart: unless-stopped
    ports:
      - "6379:6379"       # expose to host for redis-cli access
    volumes:
      - redis-app1-data:/data
    command: >
      redis-server
      --requirepass "${REDIS_APP1_PASSWORD}"
      --maxmemory 512mb
      --maxmemory-policy allkeys-lru
      --save ""
      --appendonly no
    networks:
      - redis-net

  redis-app2:
    image: redis:8.0-alpine
    container_name: redis-app2
    restart: unless-stopped
    ports:
      - "6380:6379"       # mapped to 6380 on host; still :6379 inside Docker
    volumes:
      - redis-app2-data:/data
    command: >
      redis-server
      --requirepass "${REDIS_APP2_PASSWORD}"
      --maxmemory 512mb
      --maxmemory-policy allkeys-lru
      --save ""
      --appendonly no
    networks:
      - redis-net

  redis-insight:
    image: redis/redisinsight:latest
    container_name: redis-insight
    restart: unless-stopped
    ports:
      - "5540:5540"
    volumes:
      - redis-insight-data:/data
    depends_on:
      - redis-app1
      - redis-app2
    networks:
      - redis-net

networks:
  redis-net:
    driver: bridge

volumes:
  redis-app1-data:
  redis-app2-data:
  redis-insight-data:
```

**`.env`** (create alongside `docker-compose.yml`, never commit):

```bash
REDIS_APP1_PASSWORD=StrongPass1!
REDIS_APP2_PASSWORD=StrongPass2!
```

**Start the stack:**

```bash
docker compose up -d
```

**Verify all containers are running:**

```bash
docker compose ps
```

Open `http://localhost:5540` to see the Redis Insight UI.

---

## 3. Adding Databases in the UI

When Redis Insight opens the first time, click **+ Add Redis database**.

> Inside Docker Compose, use the **container name** as the host, not `localhost`.
> Docker's internal DNS resolves container names automatically.

**App 1:**
```
Host:     redis-app1
Port:     6379
Name:     App 1 Redis
Password: StrongPass1!
```

**App 2:**
```
Host:     redis-app2
Port:     6379           ← 6379 inside Docker, even though host maps it to 6380
Name:     App 2 Redis
Password: StrongPass2!
```

Click **Test Connection**, then **Add Redis Database** for each.

---

## 4. Persisting Connections

Redis Insight saves connection profiles in its `/data` volume (`redis-insight-data`).
They survive container restarts and re-creates as long as the named volume is not
deleted.

To wipe all saved connections and start fresh:

```bash
docker compose down -v   # WARNING: deletes all named volumes
docker compose up -d
```

---

## 5. Useful Commands

```bash
# Tail Redis Insight logs
docker logs -f redis-insight

# Check Redis is responding (App 1)
docker exec redis-app1 redis-cli -a "$REDIS_APP1_PASSWORD" ping

# Check key count (App 2)
docker exec redis-app2 redis-cli -a "$REDIS_APP2_PASSWORD" dbsize

# Stop the stack without removing volumes
docker compose stop

# Restart after stopping
docker compose start
```

---

## Security Note

This setup exposes Redis Insight on `0.0.0.0:5540` with **no authentication**. That
is acceptable on a developer laptop behind a firewall, but not on a shared server or
any machine with a public IP.

To add Nginx Basic Auth in front of Redis Insight, follow [03_nginx_proxy](../03_nginx_proxy/README.md).
