# Redis Insight — Nginx Proxy (Docker)

All three services — Redis, Redis Insight, and Nginx — run as Docker containers on the
same host. Nginx is the only container that binds a public port. Redis Insight uses
`expose` (internal only), so it is never reachable directly from outside.

---

## Architecture

```
  Developer Browser
        │
        │  http://<HOST_IP>:5540
        ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  Docker Host                                                │
  │                                                             │
  │  ┌──────────────────────┐                                   │
  │  │   Nginx              │ ←── Basic Auth prompt             │
  │  │   (0.0.0.0:5540)     │     Username + Password required  │
  │  └──────────┬───────────┘                                   │
  │             │  http://redis-insight:5540 (Docker DNS)       │
  │             ▼                                               │
  │  ┌──────────────────────┐                                   │
  │  │   Redis Insight      │  ← internal only (expose)         │
  │  │   (:5540)            │                                   │
  │  └──────────┬───────────┘                                   │
  │             │  TCP on redis-net                             │
  │      ┌──────┴──────┐                                        │
  │      ▼             ▼                                        │
  │  ┌──────────┐  ┌──────────┐                                 │
  │  │  redis-  │  │  redis-  │                                 │
  │  │  app1    │  │  app2    │  ...                            │
  │  │  :6379   │  │  :6380   │                                 │
  │  └──────────┘  └──────────┘                                 │
  └─────────────────────────────────────────────────────────────┘
```

---

## Files in This Directory

```
01_docker/
├── README.md               ← you are here
├── docker-compose.yml
└── nginx/
    └── redis-insight.conf
```

---
## Install docker
```bash

sudo apt update
sudo apt install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker

sudo apt install docker-compose
```

## Step 1 — Create the `.env` File

Create `.env` next to `docker-compose.yml`. **Never commit this file.**

```bash
REDIS_APP1_PASSWORD=StrongAppOnePass!
REDIS_APP2_PASSWORD=StrongAppTwoPass!
```

---

## Step 2 — Generate the Basic Auth Password File

```bash
mkdir -p nginx

docker run --rm httpd:2.4-alpine \
  htpasswd -nbB admin 'luuqhRvqypp4TivQ2wwQARcJvWtBDesA!' \
  > nginx/.htpasswd
```

To add a second user (append, not overwrite):

```bash
docker run --rm httpd:2.4-alpine \
  htpasswd -nbB developer 'AnotherStrongPass!' \
  >> nginx/.htpasswd
```

---

## Step 3 — Start the Stack

```bash
docker compose up -d
docker compose ps
```

Expected:

```
NAME                   STATUS          PORTS
redis-app1             Up              0.0.0.0:6379->6379/tcp
redis-app2             Up              0.0.0.0:6380->6379/tcp
redis-insight          Up              (internal only)
redis-insight-proxy    Up              0.0.0.0:5540->80/tcp
```

---

## Step 4 — Open the UI

Navigate to `http://<HOST_IP>:5540`. Enter your credentials when prompted.

---

## Step 5 — Add Redis Databases

Use **container names** as the host (Docker DNS resolves them internally):

**App 1:**
```
Host:     redis-app1
Port:     6379
Password: StrongAppOnePass!
```

**App 2:**
```
Host:     redis-app2
Port:     6379
Password: StrongAppTwoPass!
```

---

## Rotating the UI Password

```bash
# Regenerate
docker run --rm httpd:2.4-alpine \
  htpasswd -nbB admin 'NewPassword!' \
  > nginx/.htpasswd

# Reload Nginx (no downtime)
docker compose exec redis-insight-proxy nginx -s reload
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| 401 — credentials not accepted | Regenerate `.htpasswd`; check for trailing whitespace |
| 502 Bad Gateway | Redis Insight container not running — `docker compose ps` |
| DB connect fails after login | Use container name as host, not `localhost` |
| Browser hangs | `Upgrade` / `Connection` headers missing from Nginx config |
