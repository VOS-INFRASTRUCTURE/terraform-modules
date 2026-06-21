#!/bin/bash
# ==============================================================================
# Redis Liveness & Health Check Script
# ==============================================================================
#
# Hierarchical health checking for Redis instances:
#   1. TCP Socket Connectivity Check
#   2. Redis PING Response (with Authentication)
#   3. Systemd Service Status (Optional)
#   4. Metrics Overview (Optional, only if instance is live)
#
# Exit Codes:
#   0 - Healthy & Responsive
#   1 - Usage Error
#   2 - TCP Connection Failed
#   3 - Redis PING Failed (e.g. timeout, wrong credentials, or frozen engine)
#   4 - Systemd Service Inactive
#
# Usage:
#   ./redis-health-check.sh -p <port> [-a <password> | -f <password_file>] [-s <service_name>] [--metrics]
#
# Examples:
#   # Basic check for default port 6379:
#   ./redis-health-check.sh
#
#   # Check specific port with password:
#   ./redis-health-check.sh -p 6380 -a "myStrongPassword"
#
#   # Check with systemd status and print metrics if healthy:
#   ./redis-health-check.sh -p 6380 -f /etc/redis/passwords/port-6380 -s redis-app2 --metrics
# ==============================================================================

set -eo pipefail

# --- Defaults ---
PORT=6379
HOST="127.0.0.1"
PASSWORD=""
PASSWORD_FILE=""
SERVICE_NAME=""
SHOW_METRICS=false
QUIET=false

# --- Help Menu ---
show_help() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -h, --help            Show this help message.
  -p, --port PORT       Redis port to check (default: 6379).
  -host, --host HOST    Redis host to check (default: 127.0.0.1).
  -a, --auth PASS       Redis AUTH password.
  -f, --pass-file FILE  Path to file containing the Redis password.
  -s, --service NAME    Systemd service name to check (e.g. redis-server or redis-app1).
  -m, --metrics         Show performance metrics if the liveness check passes.
  -q, --quiet           Quiet mode. Suppress normal output. Exit code reflects status.
EOF
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -p|--port)
      PORT="$2"
      shift 2
      ;;
    -host|--host)
      HOST="$2"
      shift 2
      ;;
    -a|--auth)
      PASSWORD="$2"
      shift 2
      ;;
    -f|--pass-file)
      PASSWORD_FILE="$2"
      shift 2
      ;;
    -s|--service)
      SERVICE_NAME="$2"
      shift 2
      ;;
    -m|--metrics)
      SHOW_METRICS=true
      shift
      ;;
    -q|--quiet)
      QUIET=true
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      show_help >&2
      exit 1
      ;;
  esac
done

# --- Helper Logger ---
log_info() {
  if [ "$QUIET" = false ]; then
    echo -e "\e[32m✓\e[0m $1"
  fi
}

log_error() {
  echo -e "\e[31m✗ ERROR:\e[0m $1" >&2
}

# --- Resolve Password ---
if [ -n "$PASSWORD_FILE" ]; then
  if [ -f "$PASSWORD_FILE" ]; then
    PASSWORD=$(cat "$PASSWORD_FILE" | tr -d '\r\n')
  else
    log_error "Password file not found at: $PASSWORD_FILE"
    exit 1
  fi
fi

# ==============================================================================
# STAGE 1: TCP Socket Check
# ==============================================================================
if command -v nc >/dev/null 2>&1; then
  if ! nc -z -w 3 "$HOST" "$PORT" >/dev/null 2>&1; then
    log_error "TCP port $PORT on $HOST is NOT reachable/listening."
    exit 2
  fi
else
  # Fallback to bash socket if nc is not present
  if ! (timeout 3 bash -c "cat < /dev/null > /dev/tcp/$HOST/$PORT" 2>/dev/null); then
    log_error "TCP port $PORT on $HOST is NOT reachable/listening."
    exit 2
  fi
fi

log_info "TCP connection to $HOST:$PORT succeeded."

# ==============================================================================
# STAGE 2: Redis PING Check
# ==============================================================================
PING_CMD=("redis-cli" "-h" "$HOST" "-p" "$PORT")
if [ -n "$PASSWORD" ]; then
  # Pass password via REDISCLI_AUTH environment variable to avoid exposing it in ps
  export REDISCLI_AUTH="$PASSWORD"
fi

# Run PING with a short timeout
PING_RESPONSE=$(timeout 4 "${PING_CMD[@]}" PING 2>/dev/null || true)

# Unset environment variable containing credentials
unset REDISCLI_AUTH

if [ "$PING_RESPONSE" != "PONG" ]; then
  log_error "Redis instance at $HOST:$PORT is not responding to PING. Response: '$PING_RESPONSE'"
  exit 3
fi

log_info "Redis is responding to PING (PONG)."

# ==============================================================================
# STAGE 3: Optional Systemd Service Check
# ==============================================================================
if [ -n "$SERVICE_NAME" ]; then
  if command -v systemctl >/dev/null 2>&1; then
    if ! systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1; then
      log_error "Systemd service '$SERVICE_NAME' is registered but is NOT active."
      exit 4
    fi
    log_info "Systemd service '$SERVICE_NAME' is active."
  else
    log_error "systemctl command not found. Cannot verify service '$SERVICE_NAME'."
    exit 1
  fi
fi

# ==============================================================================
# STAGE 4: Optional Metrics Collection (Prints if -m / --metrics is enabled)
# ==============================================================================
if [ "$SHOW_METRICS" = true ]; then
  # Helper to run info command safely
  run_redis_info() {
    local section="$1"
    if [ -n "$PASSWORD" ]; then
      export REDISCLI_AUTH="$PASSWORD"
    fi
    redis-cli -h "$HOST" -p "$PORT" INFO "$section" 2>/dev/null || true
    unset REDISCLI_AUTH
  }

  echo ""
  echo "=== Telemetry Metrics for Port $PORT ==="

  # Fetch sections
  MEM_INFO=$(run_redis_info memory)
  STAT_INFO=$(run_redis_info stats)
  CLI_INFO=$(run_redis_info clients)
  KEY_INFO=$(run_redis_info keyspace)

  # Parse Memory
  used_bytes=$(echo "$MEM_INFO" | grep "^used_memory:" | cut -d: -f2 | tr -d '\r\n ')
  max_bytes=$(echo "$MEM_INFO" | grep "^maxmemory:" | cut -d: -f2 | tr -d '\r\n ')
  frag_ratio=$(echo "$MEM_INFO" | grep "^mem_fragmentation_ratio:" | cut -d: -f2 | tr -d '\r\n ')
  policy=$(echo "$MEM_INFO" | grep "^maxmemory_policy:" | cut -d: -f2 | tr -d '\r\n ')

  used_human=$(echo "$MEM_INFO" | grep "^used_memory_human:" | cut -d: -f2 | tr -d '\r\n ')
  max_human=$(echo "$MEM_INFO" | grep "^maxmemory_human:" | cut -d: -f2 | tr -d '\r\n ')

  # Parse Stats
  evicted=$(echo "$STAT_INFO" | grep "^evicted_keys:" | cut -d: -f2 | tr -d '\r\n ')
  hits=$(echo "$STAT_INFO" | grep "^keyspace_hits:" | cut -d: -f2 | tr -d '\r\n ')
  misses=$(echo "$STAT_INFO" | grep "^keyspace_misses:" | cut -d: -f2 | tr -d '\r\n ')

  # Parse Clients
  clients=$(echo "$CLI_INFO" | grep "^connected_clients:" | cut -d: -f2 | tr -d '\r\n ')

  # Calculate Memory Usage %
  pct=0
  if [ -n "$used_bytes" ] && [ -n "$max_bytes" ] && [ "$max_bytes" -gt 0 ]; then
    pct=$((used_bytes * 100 / max_bytes))
  fi

  # Calculate Cache Hit Rate
  hit_rate=0
  if [ -n "$hits" ] && [ -n "$misses" ]; then
    total_ops=$((hits + misses))
    if [ "$total_ops" -gt 0 ]; then
      hit_rate=$((hits * 100 / total_ops))
    fi
  fi

  # Print Summary Table
  printf "%-25s : %s\n" "Memory Used" "$used_human"
  printf "%-25s : %s\n" "Max Memory Limit" "$max_human"
  printf "%-25s : %d%%\n" "Memory Used %" "$pct"
  printf "%-25s : %s\n" "Fragmentation Ratio" "$frag_ratio"
  printf "%-25s : %s\n" "Eviction Policy" "$policy"
  printf "%-25s : %s\n" "Total Evicted Keys" "${evicted:-0}"
  printf "%-25s : %d%%\n" "Cache Hit Rate" "$hit_rate"
  printf "%-25s : %s\n" "Connected Clients" "${clients:-0}"
  echo ""
  echo "Keyspaces per Database:"
  if [ -n "$KEY_INFO" ]; then
    echo "$KEY_INFO" | grep -v "^#" | grep -v "^$" | sed 's/^/  /'
  else
    echo "  (No active databases/keys)"
  fi
fi

exit 0
