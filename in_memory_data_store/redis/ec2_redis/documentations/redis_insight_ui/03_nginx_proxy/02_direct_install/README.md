# Redis Insight — Nginx Proxy (Direct Install on EC2)

Redis and Redis Insight both run as native systemd services on the same EC2 instance
deployed by this Terraform module. Nginx (also installed natively) sits in front of
Redis Insight and enforces Basic Auth. An Application Load Balancer (ALB) handles
SSL termination and is the only publicly reachable entry point.

---

## Architecture

```
  Developer Browser
        │
        │  HTTPS :443
        ▼
  ┌──────────────────────────────────────┐
  │  Application Load Balancer (ALB)     │
  │  - Listener: HTTPS :443              │
  │  - SSL certificate (ACM)             │
  │  - Target group → EC2 :80           │
  │  - Health check: HTTP GET /          │
  └──────────────────┬───────────────────┘
                     │  HTTP :80
                     │  (ALB SG → EC2 SG only)
                     ▼
  ┌──────────────────────────────────────────────────────┐
  │  EC2 Instance (Ubuntu 24.04 ARM64)                   │
  │                                                      │
  │  ┌────────────────────────────────────────────────┐  │
  │  │  Nginx  (0.0.0.0:80)                           │  │
  │  │  - Basic Auth                                  │  │
  │  │  - Trusts X-Forwarded-Proto from ALB           │  │
  │  └──────────────────────┬─────────────────────────┘  │
  │                         │  http://127.0.0.1:5540      │
  │                         ▼                             │
  │  ┌────────────────────────────────────────────────┐  │
  │  │  Redis Insight  (127.0.0.1:5540)               │  │
  │  │  - Bound to loopback only                      │  │
  │  │  - Runs as systemd service                     │  │
  │  └──────────────────────┬─────────────────────────┘  │
  │                         │  127.0.0.1:6379             │
  │                         ▼                             │
  │  ┌────────────────────────────────────────────────┐  │
  │  │  Redis  (127.0.0.1:6379)                       │  │
  │  │  - Deployed by this Terraform module           │  │
  │  │  - Bound to 0.0.0.0 for app access,            │  │
  │  │    but protected by Security Group             │  │
  │  └────────────────────────────────────────────────┘  │
  └──────────────────────────────────────────────────────┘
```

**Security boundary summary:**
- ALB SG: allows inbound HTTPS from `0.0.0.0/0`
- EC2 SG: allows inbound HTTP `:80` from **ALB SG only** — no direct public access
- Redis port `:6379` is never exposed through the ALB; only app servers reach it via their own SG rules

---

## Files in This Directory

```
02_direct_install/
├── README.md                ← you are here
└── nginx/
    └── redis-insight.conf   ← drop into /etc/nginx/sites-available/
```

---

## Step 1 — Install Redis Insight

Redis Insight is distributed as a Linux AppImage. The EC2 instance uses ARM64
(t4g / r6g), so you need the `arm64` build.

```bash
# Create a dedicated user (no login shell, no home dir)
sudo useradd --system --no-create-home --shell /usr/sbin/nologin redisinsight

# Create install directory
sudo mkdir -p /opt/redisinsight
sudo mkdir -p /var/lib/redisinsight

# Download the ARM64 AppImage
sudo wget -q \
  https://downloads.redis.io/redis-insight/latest/redisinsight-linux-arm64.AppImage \
  -O /opt/redisinsight/redisinsight.AppImage

sudo chmod +x /opt/redisinsight/redisinsight.AppImage
```

AppImages require FUSE2. Rather than installing FUSE on a server, extract the
AppImage to get a plain directory of files:

```bash
cd /opt/redisinsight

# Extract AppImage contents (no FUSE required after this)
sudo ./redisinsight.AppImage --appimage-extract

# The app is now at /opt/redisinsight/squashfs-root/redisinsight
sudo mv squashfs-root app
sudo rm redisinsight.AppImage

# Hand ownership to the service user
sudo chown -R redisinsight:redisinsight /opt/redisinsight /var/lib/redisinsight
```

---

## Step 2 — Create the Redis Insight Systemd Service

```bash
sudo tee /etc/systemd/system/redisinsight.service > /dev/null <<'EOF'
[Unit]
Description=Redis Insight UI
Documentation=https://redis.io/docs/connect/insight/
After=network.target redis-server.service
Wants=redis-server.service

[Service]
Type=simple
User=redisinsight
Group=redisinsight
WorkingDirectory=/opt/redisinsight/app

ExecStart=/opt/redisinsight/app/redisinsight

Restart=on-failure
RestartSec=5

# Bind to loopback only — Nginx is the only public entry point
Environment=RI_APP_HOST=127.0.0.1
Environment=RI_APP_PORT=5540

# Data and log directories
Environment=RI_FILES_LOGGER_DIRNAME=/var/lib/redisinsight
Environment=RI_LOG_LEVEL=warn

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable redisinsight
sudo systemctl start redisinsight
```

Verify it started:

```bash
sudo systemctl status redisinsight
# Should show: Active: active (running)

# Confirm it's listening only on loopback
ss -tlnp | grep 5540
# Expected: 127.0.0.1:5540
```

---

## Step 3 — Install Nginx

```bash
sudo apt-get update
sudo apt-get install -y nginx apache2-utils
```

---

## Step 4 — Generate the Basic Auth Password File

```bash
# Create the password file with your chosen username
sudo htpasswd -cB /etc/nginx/.htpasswd admin
# You will be prompted to enter and confirm the password

# To add a second user (append, not overwrite — no -c flag)
sudo htpasswd -B /etc/nginx/.htpasswd developer

# Lock down the file so only nginx (root) can read it
sudo chmod 640 /etc/nginx/.htpasswd
sudo chown root:www-data /etc/nginx/.htpasswd
```

---

## Step 5 — Configure Nginx

Copy `nginx/redis-insight.conf` from this directory to the server:

```bash
sudo cp redis-insight.conf /etc/nginx/sites-available/redis-insight
sudo ln -s /etc/nginx/sites-available/redis-insight /etc/nginx/sites-enabled/redis-insight

# Disable the default site if it exists
sudo rm -f /etc/nginx/sites-enabled/default

# Test the config
sudo nginx -t

# Reload (no downtime)
sudo systemctl reload nginx
```

---

## Step 6 — Security Group Rules

In Terraform (or the AWS console), the EC2 security group needs:

```hcl
# Allow ALB to reach Nginx
ingress {
  from_port       = 80
  to_port         = 80
  protocol        = "tcp"
  security_groups = [aws_security_group.alb.id]   # ALB SG only — not 0.0.0.0/0
}
```

The ALB security group needs:

```hcl
ingress {
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}
```

> Redis port 6379 must **not** be added to the ALB or any internet-facing rule.

---

## Step 7 — ALB Setup

1. Create a **Target Group**:
   - Target type: `Instance`
   - Protocol: `HTTP`, Port: `80`
   - Health check path: `/` (Nginx returns 401 which counts as healthy — set matcher to `200-401`)

2. Create an **Application Load Balancer**:
   - Scheme: `internet-facing`
   - Listener: `HTTPS :443` with your ACM certificate
   - Forward to the target group above

3. Register your EC2 instance in the target group.

---

## Step 8 — Open the UI

Navigate to your ALB DNS name or custom domain:

```
https://redis-insight.your-domain.com
```

You will see a Basic Auth prompt. Enter the credentials from Step 4.

After logging in, click **+ Add Redis database**:

```
Host:     127.0.0.1      ← Redis Insight and Redis are on the same host
Port:     6379
Name:     App 1
Password: <your redis_password from Terraform>
```

---

## Adding Redis Insight to the EC2 User Data (Optional)

If you want Redis Insight installed automatically when the EC2 instance launches,
you can append the Step 1–5 commands to the `user_data.tf` script in this module.
That way a fresh instance is always ready without manual SSH.

---

## Rotating the UI Password

```bash
# Change password for an existing user
sudo htpasswd -B /etc/nginx/.htpasswd admin

# Reload Nginx to pick up the change (no downtime)
sudo systemctl reload nginx
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| ALB health check failing | Set health check matcher to `200-401`; Nginx returns 401 when no credentials are sent |
| 502 Bad Gateway from ALB | Nginx is not running — `sudo systemctl status nginx` |
| 502 from Nginx | Redis Insight is not running — `sudo systemctl status redisinsight` |
| 401 — credentials not accepted | Regenerate `.htpasswd`; check file permissions (`640`, owner `root:www-data`) |
| Redis Insight binds to 0.0.0.0 | Ensure `RI_APP_HOST=127.0.0.1` is set in the systemd service |
| DB connect fails inside UI | Use `127.0.0.1` as host (both services on the same machine) |
| AppImage won't run | Run `--appimage-extract` to unpack it; no FUSE needed for the extracted binary |
