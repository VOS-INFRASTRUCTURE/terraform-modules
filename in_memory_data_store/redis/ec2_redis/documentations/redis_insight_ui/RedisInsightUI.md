# Redis Insight UI — Overview

Redis Insight is Redis's official GUI for exploring, querying, and monitoring Redis
instances. It runs as a local desktop app or as a Docker container with a browser-based
UI on port **5540**.
https://redis.io/docs/latest/develop/tools/insight/
---

## What You Can Do With It

| Feature | Detail |
|---------|--------|
| Browse keys | Explore all keys across databases with filtering and search |
| Run commands | Interactive CLI with auto-complete against a live instance |
| View memory | Per-key and per-type memory breakdown |
| Monitor streams | Real-time `MONITOR` output and Pub/Sub inspector |
| Profiler | Capture live command throughput |
| Multi-database | Connect to multiple Redis instances simultaneously |
| Auth support | Password-protected instances via `requirepass` |

---

## Installation Paths

```
                     Redis Insight
                          │
           ┌──────────────┴──────────────┐
           │                             │
   Direct Install                     Docker
   (desktop app)                (headless, browser UI)
           │                             │
   Connect via                  ┌────────┴────────┐
   SSH Tunnel                   │                 │
                            No auth          Nginx Proxy
                           (local dev)      (shared / remote)
```

| Approach | Best For |
|----------|----------|
| [Direct Install](01_direct_install/README.md) | Individual developers connecting to a remote EC2 Redis over an SSH tunnel |
| [Docker (simple)](02_docker/README.md) | Local dev stacks with Redis running in Docker alongside your app |
| [Docker + Nginx Proxy](03_nginx_proxy/README.md) | Shared environments, EC2-hosted Redis Insight, or any setup requiring login |

---

## How Redis Insight Connects to Redis

Redis Insight is only a **client** — it does not run inside Redis. It connects over TCP
to any Redis instance it is configured to reach, the same way `redis-cli` does.

```
  Redis Insight (UI)
        │
        │  TCP :6379 (or custom port)
        │  + password (if requirepass is set)
        ▼
  Redis Server
```

When the Redis server is on a remote EC2 instance (as deployed by this module), you have
two options to reach it:

1. **SSH tunnel** (recommended for direct installs) — see [01_direct_install](01_direct_install/README.md)
2. **Redis Insight on the same EC2 host** behind a reverse proxy — see [03_nginx_proxy](03_nginx_proxy/README.md)

---

## Securing the Redis Insight UI

Redis Insight itself has no built-in login screen for the web UI. If you expose it
beyond `localhost`, you must add a reverse proxy with authentication in front of it.

The recommended approach for this module is **Nginx Basic Auth** — lightweight, no
extra dependencies, and sufficient for internal tooling.

See [03_nginx_proxy](03_nginx_proxy/README.md) for the full setup.

---

## Quick Reference — Default Ports

| Service | Default Port |
|---------|-------------|
| Redis Insight web UI | `5540` |
| Redis (App 1) | `6379` |
| Redis (App 2) | `6380` |
| Redis (App N) | `6378 + N` |
