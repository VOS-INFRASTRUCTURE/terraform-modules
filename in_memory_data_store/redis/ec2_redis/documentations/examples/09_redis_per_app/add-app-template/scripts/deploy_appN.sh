#!/bin/bash
# Template deploy script for adding a new Redis app process to the shared host.
# Run via SSM Session Manager after 'terraform apply'.
#
# Before running: set APP_NUMBER and REDIS_PORT to match the new app.
#
# Usage:
#   APP_N_PASS=$(terraform output -raw appN_redis_password)
#   sudo bash deploy_appN.sh "$APP_N_PASS"

set -euo pipefail

# ── Configure these two values before running ───────────────────────────────
APP_NUMBER=3       # e.g. 3, 4, 5 ...
REDIS_PORT=6381    # e.g. 6381, 6382, 6383 ...
# ────────────────────────────────────────────────────────────────────────────

APP_PASSWORD="${1:?Usage: sudo bash $0 <appN_redis_password>}"
APP_NAME="app${APP_NUMBER}"
SERVICE_NAME="redis-${APP_NAME}"
CONF_FILE="/etc/redis/${APP_NAME}.conf"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
DATA_DIR="/var/lib/redis/${APP_NAME}"
LOG_FILE="/var/log/redis/${APP_NAME}.log"
PID_FILE="/var/run/redis/${SERVICE_NAME}.pid"

echo "=== Deploying Redis ${APP_NAME} on port ${REDIS_PORT} ==="

echo "--- Step 1: Create data directory ---"
sudo mkdir -p "${DATA_DIR}"
sudo chown redis:redis "${DATA_DIR}"
sudo chmod 750 "${DATA_DIR}"

echo "--- Step 2: Write ${CONF_FILE} ---"
sudo tee "${CONF_FILE}" > /dev/null <<CONF
# Redis config — ${APP_NAME} (port ${REDIS_PORT})
# Written by deploy_appN.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")

bind 0.0.0.0
port ${REDIS_PORT}
protected-mode yes
tcp-backlog 511
timeout 0
tcp-keepalive 300

daemonize yes
supervised systemd
pidfile ${PID_FILE}
loglevel notice
logfile ${LOG_FILE}

maxmemory 512mb
maxmemory-policy allkeys-lru

# DB 0  REDIS_DB=0                  Default / fallback (Laravel Redis facade)
# DB 1  REDIS_CACHE_DB=1            Application cache
# DB 2  REDIS_SESSION_DB=2          User sessions
# DB 3  REDIS_QUEUE_DB=3            Queue jobs (Horizon workers)
# DB 4  REDIS_HORIZON_DB=4          Horizon metrics, failed jobs, worker status
# DB 5  REDIS_SCHEDULER_LOCK_DB=5   onOneServer() scheduler locks
databases 6

save 900 1
save 300 10
save 60 10000
dbfilename dump-${APP_NAME}.rdb
dir ${DATA_DIR}

appendonly yes
appendfilename "appendonly-${APP_NAME}.aof"
appendfsync everysec

requirepass ${APP_PASSWORD}

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

sudo chown redis:redis "${CONF_FILE}"
sudo chmod 640 "${CONF_FILE}"
echo "Config written to ${CONF_FILE}"

echo "--- Step 3: Write ${SERVICE_FILE} ---"
sudo tee "${SERVICE_FILE}" > /dev/null <<SERVICE
[Unit]
Description=Redis In-Memory Store — ${APP_NAME} (port ${REDIS_PORT})
After=network.target
Documentation=https://redis.io/docs

[Service]
Type=forking
ExecStart=/usr/bin/redis-server ${CONF_FILE}
ExecStop=/usr/bin/redis-cli -p ${REDIS_PORT} -a '${APP_PASSWORD}' shutdown nosave
PIDFile=${PID_FILE}
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

echo "Service unit written to ${SERVICE_FILE}"

echo "--- Step 4: Enable and start ${SERVICE_NAME} ---"
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}"
sudo systemctl start  "${SERVICE_NAME}"

sleep 3

echo "--- Step 5: Verify ---"
sudo systemctl status "${SERVICE_NAME}" --no-pager

echo ""
PING=$(redis-cli -p "${REDIS_PORT}" -a "${APP_PASSWORD}" ping 2>/dev/null)
if [ "$PING" = "PONG" ]; then
  echo "✓ ${APP_NAME} Redis is responding on port ${REDIS_PORT}"
else
  echo "✗ redis-cli ping returned: $PING"
  echo "  Check logs: sudo journalctl -u ${SERVICE_NAME} -n 50"
  exit 1
fi

echo ""
echo "=== ${APP_NAME} setup complete ==="
echo "  Port:      ${REDIS_PORT}"
echo "  Data dir:  ${DATA_DIR}"
echo "  Log file:  ${LOG_FILE}"
echo ""
echo "Next steps:"
echo "  1. Run scripts/02_update_cloudwatch.sh to ship ${APP_NAME} logs to CloudWatch"
echo "  2. Run scripts/03_verify.sh to confirm isolation from other apps"
