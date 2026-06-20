#!/bin/bash
# Run this on the Redis host via SSM Session Manager after 'terraform apply'.
#
# Usage:
#   APP2_PASS=$(terraform output -raw app2_redis_password)
#   sudo bash 01_deploy_app2.sh "$APP2_PASS"
#
# What this script does:
#   1. Creates the App 2 data directory (/var/lib/redis/app2)
#   2. Writes /etc/redis/app2.conf with the real password substituted
#   3. Writes /etc/systemd/system/redis-app2.service
#   4. Enables and starts the redis-app2 systemd unit
#   5. Confirms App 2 is responding on port 6380

set -euo pipefail

APP2_PASSWORD="${1:?Usage: sudo bash $0 <app2_redis_password>}"

echo "=== Step 1: Create isolated data directory ==="
sudo mkdir -p /var/lib/redis/app2
sudo chown redis:redis /var/lib/redis/app2
sudo chmod 750 /var/lib/redis/app2

echo "=== Step 2: Write /etc/redis/app2.conf ==="
sudo tee /etc/redis/app2.conf > /dev/null <<CONF
# App 2 Redis config — port 6380
# Written by 01_deploy_app2.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")

bind 0.0.0.0
port 6380
protected-mode yes
tcp-backlog 511
timeout 0
tcp-keepalive 300

daemonize yes
supervised systemd
pidfile /var/run/redis/redis-app2.pid
loglevel notice
logfile /var/log/redis/app2.log

maxmemory 700mb
maxmemory-policy allkeys-lru
databases 4

save 900 1
save 300 10
save 60 10000
dbfilename dump-app2.rdb
dir /var/lib/redis/app2

appendonly yes
appendfilename "appendonly-app2.aof"
appendfsync everysec

requirepass ${APP2_PASSWORD}

rename-command FLUSHALL  ""
rename-command FLUSHDB   ""
rename-command CONFIG    ""
rename-command DEBUG     ""
rename-command SLAVEOF   ""
rename-command REPLICAOF ""

slowlog-log-slower-than 10000
slowlog-max-len 128
hz 20
dynamic-hz yes
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
maxclients 500
CONF

sudo chown redis:redis /etc/redis/app2.conf
sudo chmod 640 /etc/redis/app2.conf
echo "Config written."

echo "=== Step 3: Write /etc/systemd/system/redis-app2.service ==="
sudo tee /etc/systemd/system/redis-app2.service > /dev/null <<SERVICE
[Unit]
Description=Redis In-Memory Store — App 2 (port 6380)
After=network.target
Documentation=https://redis.io/docs

[Service]
Type=forking
ExecStart=/usr/bin/redis-server /etc/redis/app2.conf
ExecStop=/usr/bin/redis-cli -p 6380 -a '${APP2_PASSWORD}' shutdown nosave
PIDFile=/var/run/redis/redis-app2.pid
TimeoutStartSec=30
TimeoutStopSec=30
Restart=always
RestartSec=5
User=redis
Group=redis
RuntimeDirectory=redis
RuntimeDirectoryMode=0755
UMask=007
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICE

echo "Service unit written."

echo "=== Step 4: Enable and start redis-app2 ==="
sudo systemctl daemon-reload
sudo systemctl enable redis-app2
sudo systemctl start redis-app2

sleep 3

echo "=== Step 5: Verify ==="
sudo systemctl status redis-app2 --no-pager

echo ""
PING=$(redis-cli -p 6380 -a "${APP2_PASSWORD}" ping 2>/dev/null)
if [ "$PING" = "PONG" ]; then
  echo "✓ App 2 Redis is responding on port 6380"
else
  echo "✗ redis-cli ping returned: $PING"
  echo "  Check logs: sudo journalctl -u redis-app2 -n 50"
  exit 1
fi

echo ""
echo "=== App 2 setup complete ==="
echo "  Host:     127.0.0.1"
echo "  Port:     6380"
echo "  Data dir: /var/lib/redis/app2"
echo "  Log file: /var/log/redis/app2.log"
echo ""
echo "Next: run 02_update_cloudwatch.sh to add App 2 logs to CloudWatch."
