#!/bin/bash
# Extend the existing CloudWatch agent config (written by the ec2_redis module's user_data)
# to also ship App 2's log file (/var/log/redis/app2.log).
#
# The module's user_data already configures the CW agent for App 1's logs.
# This script appends App 2's log stream without touching App 1's config.
#
# Usage:
#   LOG_GROUP=$(terraform output -raw redis_cloudwatch_log_group)
#   sudo bash 02_update_cloudwatch.sh "$LOG_GROUP"

set -euo pipefail

LOG_GROUP="${1:?Usage: sudo bash $0 <cloudwatch_log_group_name>}"

CW_CONFIG=/opt/aws/amazon-cloudwatch-agent/etc/cloudwatch-config.json

if [ ! -f "$CW_CONFIG" ]; then
  echo "CloudWatch agent config not found at $CW_CONFIG"
  echo "Is the ec2_redis module deployed with enable_cloudwatch_logs = true?"
  exit 1
fi

echo "=== Adding App 2 log stream to CloudWatch agent config ==="

sudo python3 - "$LOG_GROUP" "$CW_CONFIG" <<'PYEOF'
import json, sys

log_group  = sys.argv[1]
config_path = sys.argv[2]

with open(config_path) as f:
    config = json.load(f)

files = config["logs"]["logs_collected"]["files"]["collect_list"]

already_present = any(e["file_path"] == "/var/log/redis/app2.log" for e in files)

if already_present:
    print("App 2 log entry already present — no change needed.")
    sys.exit(0)

files.append({
    "file_path": "/var/log/redis/app2.log",
    "log_group_name": log_group,
    "log_stream_name": "{instance_id}/redis-app2.log",
    "timezone": "UTC"
})

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)

print(f"Added /var/log/redis/app2.log → {log_group}/{{instance_id}}/redis-app2.log")
PYEOF

echo "=== Reloading CloudWatch agent ==="
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/cloudwatch-config.json

echo ""
echo "✓ CloudWatch agent reloaded."
echo "  App 2 logs will appear in log group: ${LOG_GROUP}"
echo "  Stream name: <instance_id>/redis-app2.log"
