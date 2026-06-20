# Redis Insight — Nginx Proxy with Basic Auth

Redis Insight has no built-in login screen for its web UI. This guide puts Nginx in
front of Redis Insight and requires a username + password before the UI loads.

Use this when:
- Redis Insight runs on a shared EC2 host (not your local laptop)
- You want to access the UI via a browser without an SSH tunnel
- You need to give multiple team members access without exposing Redis Insight directly

---

## Architecture

```
  Developer Browser
        │
        │  http://<SERVER_IP>:5540
        ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  EC2 Host / Docker Host                                     │
  │                                                             │
  │  ┌──────────────────────┐                                   │
  │  │   Nginx Proxy        │ ←── Basic Auth prompt             │
  │  │   (port 5540 public) │     Username + Password required  │
  │  └──────────┬───────────┘                                   │
  │             │  http://redis-insight:5540 (internal Docker)  │
  │             ▼                                               │
  │  ┌──────────────────────┐                                   │
  │  │   Redis Insight      │  ← only reachable via Nginx       │
  │  │   (port 5540 internal│                                   │
  │  │    not exposed)      │                                   │
  │  └──────────┬───────────┘                                   │
  │             │  TCP (Docker internal network)                │
  │      ┌──────┴──────┐                                        │
  │      ▼             ▼                                        │
  │  ┌──────────┐  ┌──────────┐                                 │
  │  │  redis-  │  │  redis-  │                                 │
  │  │  app1    │  │  app2    │  ...                            │
  │  │  :6379   │  │  :6380   │                                 │
  │  └──────────┘  └──────────┘                                 │
  └─────────────────────────────────────────────────────────────┘
```

**Key point:** Redis Insight uses `expose` (not `ports`) in the Compose file so it is
only reachable from other containers on the Docker network, never directly from outside.
Nginx is the only service that binds a public port.

---

## Files in This Directory

```
03_nginx_proxy/
├── README.md               ← you are here
├── docker-compose.yml      ← full stack definition
└── nginx/
    └── redis-insight.conf  ← Nginx server block
```

---

## Step 1 — Clone / Copy the Files

Copy this entire `03_nginx_proxy/` directory to your server or local machine.

---

## Step 2 — Create the `.env` File

Create a `.env` file next to `docker-compose.yml`. **Never commit this file.**

```bash
# .env
REDIS_APP1_PASSWORD=StrongAppOnePass!
REDIS_APP2_PASSWORD=StrongAppTwoPass!
```

---

## Step 3 — Generate the Basic Auth Password File

The `.htpasswd` file stores hashed credentials that Nginx checks on every request.

Create the `nginx/` directory if it does not already exist, then generate the file:

```bash
mkdir -p nginx
```

**Using Docker (no htpasswd binary needed):**

```bash
docker run --rm httpd:2.4-alpine \
  htpasswd -nbB admin 'YourStrongUIPassword!' \
  > nginx/.htpasswd
```

This creates a user named `admin` with bcrypt-hashed password `YourStrongUIPassword!`.

**To add a second user** (append, not overwrite):

```bash
docker run --rm httpd:2.4-alpine \
  htpasswd -nbB developer 'AnotherStrongPass!' \
  >> nginx/.htpasswd
```

**Verify the file looks correct:**

```bash
cat nginx/.htpasswd
# admin:$2y$05$...hashed...
# developer:$2y$05$...hashed...
```

---

## Step 4 — Start the Stack

```bash
docker compose up -d
```

**Verify all containers started:**

```bash
docker compose ps
```

Expected output:

```
NAME                   STATUS          PORTS
redis-app1             Up              0.0.0.0:6379->6379/tcp
redis-app2             Up              0.0.0.0:6380->6379/tcp
redis-insight          Up              (no public port — internal only)
redis-insight-proxy    Up              0.0.0.0:5540->80/tcp
```

---

## Step 5 — Open the UI

Navigate to `http://<SERVER_IP>:5540` in your browser.

You will see a browser Basic Auth prompt:

```
Username: admin
Password: YourStrongUIPassword!
```

After entering valid credentials, the Redis Insight UI loads.

---

## Step 6 — Add Redis Databases in the UI

Click **+ Add Redis database** and use the container names as hosts (Docker DNS):

**App 1:**
```
Host:     redis-app1
Port:     6379
Name:     App 1
Password: StrongAppOnePass!
```

**App 2:**
```
Host:     redis-app2
Port:     6379
Name:     App 2
Password: StrongAppTwoPass!
```

---

## Rotating the UI Password

1. Regenerate `.htpasswd` with the new password:
   ```bash
   docker run --rm httpd:2.4-alpine \
     htpasswd -nbB admin 'NewStrongPassword!' \
     > nginx/.htpasswd
   ```
2. Reload Nginx (no downtime):
   ```bash
   docker compose exec redis-insight-proxy nginx -s reload
   ```

---

## Optional — Restrict Access by IP

If only your office or VPN IP should reach the UI, add an `allow` / `deny` block to
`nginx/redis-insight.conf` inside the `server` block:

```nginx
allow 203.0.113.0/24;   # your office CIDR
allow 10.0.0.0/8;       # VPN range
deny  all;
```

This is complementary to Basic Auth — both checks must pass.

---

## Optional — HTTPS with a Self-Signed Certificate

For HTTPS without a public domain:

**Generate a self-signed cert:**

```bash
mkdir -p nginx/certs
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout nginx/certs/redis-insight.key \
  -out    nginx/certs/redis-insight.crt \
  -subj "/CN=redis-insight"
```

**Update `nginx/redis-insight.conf`** to listen on 443:

```nginx
server {
    listen 443 ssl;

    ssl_certificate     /etc/nginx/certs/redis-insight.crt;
    ssl_certificate_key /etc/nginx/certs/redis-insight.key;

    auth_basic           "Redis Insight";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        proxy_pass         http://redis-insight:5540;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_set_header   Upgrade           $http_upgrade;
        proxy_set_header   Connection        "upgrade";
    }
}
```

**Mount the certs in `docker-compose.yml`:**

```yaml
redis-insight-proxy:
  volumes:
    - ./nginx/redis-insight.conf:/etc/nginx/conf.d/default.conf:ro
    - ./nginx/.htpasswd:/etc/nginx/.htpasswd:ro
    - ./nginx/certs:/etc/nginx/certs:ro
  ports:
    - "5540:443"
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| 401 Unauthorized — credentials not accepted | Re-generate `.htpasswd`; ensure no trailing whitespace in the file |
| 502 Bad Gateway | Redis Insight container is not running — check `docker compose ps` |
| UI loads but database connect fails | Use container name as host, not `localhost` |
| Browser hangs after auth | Check WebSocket headers — `Upgrade` and `Connection` must be forwarded |
| `.htpasswd` not found error in Nginx logs | Volume mount path mismatch — verify the path in `docker-compose.yml` |
