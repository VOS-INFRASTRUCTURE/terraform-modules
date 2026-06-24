# EC2 Setup — Redis Direct Install + Docker Compose

Redis runs as a systemd service directly on the EC2. Redis Insight and Netdata
run as Docker containers. This separates Redis data durability (managed by systemd,
survives Docker restarts) from the UI tooling (replaceable containers).

---

## Stack Layout on the EC2

```
  ┌────────────────────────────────────────────────────────────────────────┐
  │  EC2 Instance                                                          │
  │                                                                        │
  │  ── Operating System (Amazon Linux 2023 / Ubuntu 22.04) ───────────── │
  │                                                                        │
  │  ┌──────────────────────────────────────────────────────────────────┐  │
  │  │  systemd service: redis                                          │  │
  │  │                                                                  │  │
  │  │  /etc/redis/redis.conf                                           │  │
  │  │  ├─ bind 127.0.0.1          ← only localhost, no network         │  │
  │  │  ├─ port 6379                                                    │  │
  │  │  ├─ requirepass <password>                                       │  │
  │  │  ├─ appendonly yes          ← persistence                        │  │
  │  │  └─ appendfsync everysec                                         │  │
  │  │                                                                  │  │
  │  │  Data: /var/lib/redis/                                           │  │
  │  └──────────────────────────────────────────────────────────────────┘  │
  │                                                                        │
  │  ── Docker (Docker Compose) ───────────────────────────────────────── │
  │                                                                        │
  │  ┌───────────────────────────────┐  ┌──────────────────────────────┐  │
  │  │  redis-insight                │  │  netdata                     │  │
  │  │                               │  │                              │  │
  │  │  Port: 5540                   │  │  Port: 19999                 │  │
  │  │  Connects to Redis via        │  │  PID: host                   │  │
  │  │  host.docker.internal:6379    │  │  Volumes: /proc, /sys, ...   │  │
  │  │  (same EC2 host)              │  │  (reads host metrics)        │  │
  │  │                               │  │                              │  │
  │  │  Data vol: redis-insight-data │  │                              │  │
  │  └───────────────────────────────┘  └──────────────────────────────┘  │
  │                                                                        │
  │  ┌──────────────────────────────────────────────────────────────────┐  │
  │  │  host.docker.internal  →  EC2's own private IP                   │  │
  │  │  (Docker's bridge to the host — used by Redis Insight)           │  │
  │  └──────────────────────────────────────────────────────────────────┘  │
  └────────────────────────────────────────────────────────────────────────┘
```

---

## Why Redis on the Host, Not in Docker

```
  ┌──────────────────────────────────────────────────────────────────────┐
  │  Risk comparison                                                     │
  │                                                                      │
  │  Redis in Docker                    Redis on host (systemd)          │
  │  ─────────────────────────────────  ──────────────────────────────── │
  │  Data in Docker volume               Data in /var/lib/redis/         │
  │  Volume survives container restart   survives any restart            │
  │  docker rm -v DELETES data           Cannot be accidentally deleted  │
  │  compose down --volumes DELETES data systemctl stop redis = safe     │
  │  Docker daemon crash = Redis stops   systemd restarts Redis          │
  │  Upgrade = re-pull image             Upgrade = apt upgrade redis     │
  └──────────────────────────────────────────────────────────────────────┘
```

Redis Insight is stateless (bookmarks stored in a small SQLite — not critical).
Netdata is stateless. Docker is fine for both.

---

## Step 1 — Launch the EC2

Recommended settings:

```
AMI:              Amazon Linux 2023 or Ubuntu 22.04 LTS
Instance type:    t4g.small (ARM, 2 vCPU, 2 GiB) — cheapest that handles Redis + Insight
Storage:          30 GiB gp3  root volume
                  + 100 GiB gp3  data volume (mount at /var/lib/redis)
Key pair:         your-ssh-key
Security group:   redis-ec2-sg  (see 03_cognito_alb.md)
IAM role:         attach an instance profile with SSM access (no SSH keys needed)
Subnet:           private-subnet-az-a
```

---

## Step 2 — Mount the Data Volume

```bash
# Find the data volume device (usually /dev/xvdb or /dev/nvme1n1)
lsblk

# Format (first time only — this destroys existing data)
sudo mkfs -t xfs /dev/xvdb

# Create mount point
sudo mkdir -p /var/lib/redis

# Add to /etc/fstab for auto-mount on reboot
echo "/dev/xvdb  /var/lib/redis  xfs  defaults,nofail  0  2" | sudo tee -a /etc/fstab

# Mount
sudo mount -a

# Verify
df -h /var/lib/redis
```

---

## Step 3 — Install Redis

**Amazon Linux 2023:**
```bash
sudo dnf install -y redis6
sudo systemctl enable redis
```

**Ubuntu 22.04:**
```bash
sudo apt update
sudo apt install -y redis-server
sudo systemctl enable redis-server
```

---

## Step 4 — Configure Redis

```bash
sudo nano /etc/redis/redis.conf
```

Key settings:

```conf
# Bind to localhost only — never expose Redis to the network
bind 127.0.0.1

# Standard port
port 6379

# Set a strong password
requirepass YourStrongRedisPasswordHere!

# Persistence
appendonly yes
appendfsync everysec

# Data directory (the mounted volume)
dir /var/lib/redis

# Memory limit — set to ~60% of EC2 memory
maxmemory 1gb
maxmemory-policy allkeys-lru

# Log file
logfile /var/log/redis/redis-server.log
loglevel notice
```

Fix permissions and start:

```bash
sudo chown redis:redis /var/lib/redis
sudo chmod 750 /var/lib/redis

sudo systemctl restart redis
sudo systemctl status redis

# Verify
redis-cli -a 'YourStrongRedisPasswordHere!' ping
# → PONG
```

---

## Step 5 — Install Docker

**Amazon Linux 2023:**
```bash
sudo dnf install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user
```

**Ubuntu 22.04:**
```bash
curl -fsSL https://get.docker.com | sudo bash
sudo systemctl enable --now docker
sudo usermod -aG docker ubuntu
```

Log out and back in for the group to take effect.

---

## Step 6 — Deploy the Docker Compose Stack

```bash
# Create working directory
mkdir -p /opt/redis-monitoring
cd /opt/redis-monitoring

# Create .env file — never commit this
cat > .env << 'EOF'
REDIS_PASSWORD=YourStrongRedisPasswordHere!
EOF

chmod 600 .env

# Copy docker-compose.yml here (from this repo)
# Then start
docker compose up -d
docker compose ps
```

Expected:

```
NAME             STATUS          PORTS
redis-insight    Up (healthy)    0.0.0.0:5540->5540/tcp
netdata          Up              0.0.0.0:19999->19999/tcp
```

---

## Step 7 — Add Redis to Redis Insight

Open `https://redis.prod1.company.io` in your browser.
After Cognito login, Redis Insight loads.

Add a Redis database:

```
Name:     prod1-redis
Host:     host.docker.internal
Port:     6379
Password: YourStrongRedisPasswordHere!
```

`host.docker.internal` resolves to the EC2 host's IP from inside the container,
reaching the directly-installed Redis on localhost.

---

## Persistence and Backup

Redis append-only log (`appendonly yes`) protects against crashes.
For disaster recovery, snapshot the data EBS volume periodically:

```bash
# Manual snapshot via CLI
aws ec2 create-snapshot \
  --volume-id vol-XXXXXXXXXXXXXXXXX \
  --description "redis-prod1-$(date +%Y%m%d)"

# Or create a Data Lifecycle Manager policy in the AWS Console
# EC2 → Elastic Block Store → Lifecycle Manager → Create policy
# Schedule: daily snapshot, retain 7 days
```

---

## Upgrading Redis

Since Redis is installed via the OS package manager:

```bash
# Check current version
redis-cli --version

# Upgrade
sudo dnf upgrade redis6       # Amazon Linux
sudo apt upgrade redis-server  # Ubuntu

# Restart
sudo systemctl restart redis

# Verify data integrity
redis-cli -a 'password' info server | grep redis_version
redis-cli -a 'password' dbsize
```

No containers to rebuild. Data stays in place on the EBS volume.

---

## Monitoring With Netdata

Netdata runs as a Docker container reading `/proc` and `/sys` from the host.
Access it via `https://redis.prod1.company.io/netdata/` (protected by ALB Cognito auth).

Key metrics to watch:
- **redis.net** — inbound/outbound traffic
- **redis.operations** — commands/sec
- **redis.mem** — used memory vs maxmemory
- **system.cpu** — overall host CPU
- **disk.io** — EBS volume read/write
- **mem.available** — free memory headroom
