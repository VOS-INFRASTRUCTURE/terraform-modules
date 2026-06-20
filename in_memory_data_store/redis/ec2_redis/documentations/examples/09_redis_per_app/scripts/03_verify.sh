#!/bin/bash
# Verify that the two Redis processes are isolated:
#   - Each port responds only to its own password
#   - The other app's password is rejected with WRONGPASS
#
# Run this on the Redis host (via SSM) or from any host that has network access
# to both ports.
#
# Usage:
#   APP1_PASS=$(terraform output -raw app1_redis_password)
#   APP2_PASS=$(terraform output -raw app2_redis_password)
#   bash 03_verify.sh "$APP1_PASS" "$APP2_PASS"

set -euo pipefail

APP1_PASS="${1:?Usage: bash $0 <app1_password> <app2_password>}"
APP2_PASS="${2:?}"

HOST="127.0.0.1"
PASS=0
FAIL=0

check_pong() {
  local label="$1" port="$2" pass="$3"
  local result
  result=$(redis-cli -h "$HOST" -p "$port" -a "$pass" ping 2>/dev/null || true)
  if [ "$result" = "PONG" ]; then
    echo "  ✓ PASS  $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ FAIL  $label — got: $result"
    FAIL=$((FAIL + 1))
  fi
}

check_wrongpass() {
  local label="$1" port="$2" pass="$3"
  local result
  result=$(redis-cli -h "$HOST" -p "$port" -a "$pass" ping 2>&1 || true)
  if echo "$result" | grep -q "WRONGPASS"; then
    echo "  ✓ PASS  $label — correctly rejected with WRONGPASS"
    PASS=$((PASS + 1))
  else
    echo "  ✗ FAIL  $label — expected WRONGPASS, got: $result"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Connectivity checks ==="
check_pong "App 1 (port 6379) responds to App 1 password" 6379 "$APP1_PASS"
check_pong "App 2 (port 6380) responds to App 2 password" 6380 "$APP2_PASS"

echo ""
echo "=== Isolation checks ==="
check_wrongpass "App 1 port (6379) rejects App 2 password" 6379 "$APP2_PASS"
check_wrongpass "App 2 port (6380) rejects App 1 password" 6380 "$APP1_PASS"

echo ""
echo "=== Memory usage ==="
echo "  App 1 (6379):"
redis-cli -h "$HOST" -p 6379 -a "$APP1_PASS" INFO memory 2>/dev/null \
  | grep -E "^used_memory_human|^maxmemory_human" \
  | sed 's/^/    /'

echo "  App 2 (6380):"
redis-cli -h "$HOST" -p 6380 -a "$APP2_PASS" INFO memory 2>/dev/null \
  | grep -E "^used_memory_human|^maxmemory_human" \
  | sed 's/^/    /'

echo ""
echo "=== Service status ==="
systemctl is-active redis-server  && echo "  ✓ redis-server  (App 1) is active" || echo "  ✗ redis-server  (App 1) is NOT active"
systemctl is-active redis-app2    && echo "  ✓ redis-app2    (App 2) is active" || echo "  ✗ redis-app2    (App 2) is NOT active"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
