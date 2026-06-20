# Redis Insight — Nginx Proxy (Overview)

Redis Insight has no built-in login screen. Nginx sits in front of it and enforces
Basic Auth before any request reaches the UI. Two deployment styles are covered here:

---

## Choose Your Approach

```
                    Redis Insight + Nginx
                            │
          ┌─────────────────┴──────────────────┐
          │                                    │
   ┌──────┴──────────┐                ┌────────┴────────────┐
   │  01_docker/     │                │  02_direct_install/ │
   │                 │                │                     │
   │  Redis          │                │  Redis              │
   │  (Docker)       │                │  (systemd on EC2)   │
   │       ↓         │                │         ↓           │
   │  Redis Insight  │                │  Redis Insight      │
   │  (Docker)       │                │  (systemd on EC2)   │
   │       ↓         │                │         ↓           │
   │  Nginx          │                │  Nginx              │
   │  (Docker)       │                │  (apt on EC2)       │
   │       ↓         │                │         ↓           │
   │  Browser        │                │  ALB → EC2 → Nginx  │
   └─────────────────┘                └─────────────────────┘
```

| | [01_docker](01_docker/README.md) | [02_direct_install](02_direct_install/README.md) |
|--|--|--|
| **Redis** | Docker container | Systemd service (this Terraform module) |
| **Redis Insight** | Docker container | AppImage / binary as systemd service |
| **Nginx** | Docker container | Installed via apt |
| **Entry point** | Direct IP or domain on port 5540 | ALB (HTTPS) → EC2 (HTTP :80) |
| **Best for** | Local dev stacks, self-contained Docker environments | EC2 instances deployed by this module |

---

## Shared Concept: Why Nginx?

In both approaches, Redis Insight binds only to `localhost` (or an internal Docker
network) and is never reachable directly from outside. Nginx is the only process that
accepts external connections. It checks credentials, then forwards the request inward.

```
  External traffic
        │
        ▼
  Nginx (Basic Auth gate)
        │  only proceeds if credentials match
        ▼
  Redis Insight (localhost / internal only)
        │
        ▼
  Redis instance(s)
```
