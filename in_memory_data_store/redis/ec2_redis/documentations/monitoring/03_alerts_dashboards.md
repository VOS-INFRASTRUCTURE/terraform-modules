# Redis Alerting & Dashboards (Stage 3 Monitoring)

Automated alerting and visualization allow you to notice issues (such as memory exhaustion, connection surges, or downtime) before they impact end-users.

---

## 1. Live Terminal Dashboard

To view the health of all per-app Redis ports in real-time, run this script directly on the Redis EC2 instance. It displays a live auto-updating table:

```bash
watch -n 5 '
printf "%-6s %-8s %-8s %-8s %-8s %-10s %-12s\n" \
  "PORT" "USED" "MAX" "USED%" "FRAG" "EVICTED" "HIT_RATE"
echo "────────────────────────────────────────────────────────────────"
for port in 6379 6380 6381 6382; do
  pass_file="/etc/redis/passwords/port-${port}"
  if [ -f "$pass_file" ]; then
    pass=$(cat "$pass_file")
    export REDISCLI_AUTH="$pass"
  fi
  
  used=$(redis-cli -p $port INFO memory 2>/dev/null | grep "^used_memory:" | cut -d: -f2 | tr -d "\r\n ")
  max=$(redis-cli -p $port INFO memory 2>/dev/null | grep "^maxmemory:" | cut -d: -f2 | tr -d "\r\n ")
  frag=$(redis-cli -p $port INFO memory 2>/dev/null | grep "mem_fragmentation_ratio" | cut -d: -f2 | tr -d "\r\n ")
  evicted=$(redis-cli -p $port INFO stats 2>/dev/null | grep evicted_keys | cut -d: -f2 | tr -d "\r\n ")
  hits=$(redis-cli -p $port INFO stats 2>/dev/null | grep keyspace_hits | cut -d: -f2 | tr -d "\r\n ")
  misses=$(redis-cli -p $port INFO stats 2>/dev/null | grep keyspace_misses | cut -d: -f2 | tr -d "\r\n ")

  unset REDISCLI_AUTH

  # Calculate metrics safely
  if [ -n "$used" ] && [ -n "$max" ] && [ "$max" -gt 0 ]; then
    used_mb=$((used / 1024 / 1024))
    max_mb=$((max / 1024 / 1024))
    pct=$((used_mb * 100 / max_mb))
  else
    used_mb="N/A"
    max_mb="N/A"
    pct=0
  fi
  
  if [ -n "$hits" ] && [ -n "$misses" ]; then
    total=$((hits + misses))
    if [ "$total" -gt 0 ]; then
      rate=$((hits * 100 / total))
    else
      rate=0
    fi
  else
    rate=0
  fi

  printf "%-6s %-8s %-8s %-8s %-8s %-10s %-12s\n" \
    "$port" "${used_mb}MB" "${max_mb}MB" "${pct}%" "$frag" "${evicted:-0}" "${rate}%"
done
'
```

---

## 2. CloudWatch Custom Metrics Integration

The AWS CloudWatch agent can collect and push Redis per-app metrics into CloudWatch. This enables graphing memory metrics, building CloudWatch Dashboards, and triggering Alarms.

### Metrics Push Script
Create the cron script at `/opt/redis-metrics/push-metrics.sh`:

```bash
#!/bin/bash
# Push Redis memory metrics to CloudWatch for all app instances

REGION="us-east-1"
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

declare -A PORTS=(
  [6379]="app1"
  [6380]="app2"
  [6381]="app3"
  [6382]="app4"
)

for port in "${!PORTS[@]}"; do
  app="${PORTS[$port]}"
  pass_file="/etc/redis/passwords/port-${port}"
  
  if [ -f "$pass_file" ]; then
    export REDISCLI_AUTH=$(cat "$pass_file")
  fi

  used=$(redis-cli -p $port INFO memory 2>/dev/null | grep "^used_memory:" | cut -d: -f2 | tr -d '\r ')
  max=$(redis-cli -p $port INFO memory 2>/dev/null | grep "^maxmemory:" | cut -d: -f2 | tr -d '\r ')
  evicted=$(redis-cli -p $port INFO stats 2>/dev/null | grep "evicted_keys:" | cut -d: -f2 | tr -d '\r ')

  unset REDISCLI_AUTH

  # Validate variables are numbers
  [ -n "$used" ] || used=0
  [ -n "$max" ] || max=0
  [ -n "$evicted" ] || evicted=0

  # Calculate Memory usage %
  pct=0
  [ "$max" -gt 0 ] && pct=$((used * 100 / max))

  # Push to CloudWatch
  aws cloudwatch put-metric-data \
    --region "$REGION" \
    --namespace "Redis/PerApp" \
    --metric-data \
      "[
        {\"MetricName\":\"MemoryUsedPercent\",
         \"Dimensions\":[{\"Name\":\"App\",\"Value\":\"$app\"}, {\"Name\":\"Instance\",\"Value\":\"$INSTANCE_ID\"}],
         \"Value\":$pct,\"Unit\":\"Percent\"},
        {\"MetricName\":\"EvictedKeys\",
         \"Dimensions\":[{\"Name\":\"App\",\"Value\":\"$app\"}, {\"Name\":\"Instance\",\"Value\":\"$INSTANCE_ID\"}],
         \"Value\":$evicted,\"Unit\":\"Count\"},
        {\"MetricName\":\"MemoryUsedBytes\",
         \"Dimensions\":[{\"Name\":\"App\",\"Value\":\"$app\"}, {\"Name\":\"Instance\",\"Value\":\"$INSTANCE_ID\"}],
         \"Value\":$used,\"Unit\":\"Bytes\"}
      ]"
done
```

### Install and Run
```bash
sudo mkdir -p /opt/redis-metrics
sudo chmod +x /opt/redis-metrics/push-metrics.sh

# Install every 1 minute via system cron
echo "* * * * * root /opt/redis-metrics/push-metrics.sh >> /var/log/redis-metrics.log 2>&1" \
  | sudo tee /etc/cron.d/redis-metrics
```

---

## 3. Configuring CloudWatch Alarms

Once metrics are flowing into CloudWatch, use the AWS CLI to create alarms:

### Alert: High Memory Usage (e.g. > 80% on App 2)
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "redis-app2-memory-high" \
  --alarm-description "App2 Redis memory usage above 80%" \
  --metric-name "MemoryUsedPercent" \
  --namespace "Redis/PerApp" \
  --dimensions Name=App,Value=app2 \
  --statistic Average \
  --period 60 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 3 \
  --alarm-actions "arn:aws:sns:us-east-1:123456789012:redis-alerts"
```

### Alert: High Eviction Rates (> 1000 keys in 1 min)
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "redis-app2-evictions-high" \
  --alarm-description "App2 Redis is evicting keys rapidly (data loss hazard)" \
  --metric-name "EvictedKeys" \
  --namespace "Redis/PerApp" \
  --dimensions Name=App,Value=app2 \
  --statistic Sum \
  --period 60 \
  --threshold 1000 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions "arn:aws:sns:us-east-1:123456789012:redis-alerts"
```

---

## 4. Standalone Slack Alerts (No CloudWatch Required)

For environments not using AWS CloudWatch, you can push warnings directly to a Slack webhook via cron.

Create `/opt/redis-metrics/alert-check.sh`:

```bash
#!/bin/bash

SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
THRESHOLD=85   # Alert at 85% memory usage

declare -A PORTS=([6379]="app1" [6380]="app2" [6381]="app3" [6382]="app4")

for port in "${!PORTS[@]}"; do
  app="${PORTS[$port]}"
  pass_file="/etc/redis/passwords/port-${port}"
  
  if [ -f "$pass_file" ]; then
    export REDISCLI_AUTH=$(cat "$pass_file")
  fi

  used=$(redis-cli -p $port INFO memory 2>/dev/null | grep "^used_memory:" | cut -d: -f2 | tr -d '\r ')
  max=$(redis-cli -p $port INFO memory 2>/dev/null | grep "^maxmemory:" | cut -d: -f2 | tr -d '\r ')

  unset REDISCLI_AUTH

  [ -n "$used" ] || used=0
  [ -n "$max" ] || max=0

  [ "$max" -gt 0 ] || continue
  pct=$((used * 100 / max))

  if [ "$pct" -ge "$THRESHOLD" ]; then
    curl -s -X POST "$SLACK_WEBHOOK" \
      -H 'Content-type: application/json' \
      --data "{\"text\":\"🚨 *Redis Alert* — *${app}* (port ${port}) memory is at *${pct}%* capacity. Consider increasing maxmemory limit soon!\"}"
  fi
done
```

Schedule it to run every 5 minutes:
```bash
sudo chmod +x /opt/redis-metrics/alert-check.sh
echo "*/5 * * * * root /opt/redis-metrics/alert-check.sh" \
  | sudo tee /etc/cron.d/redis-alert-check
```
