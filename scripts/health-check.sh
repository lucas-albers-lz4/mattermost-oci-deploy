#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

LOG_PREFIX="[mattermost-health]"

fail() {
  echo "$LOG_PREFIX FAIL: $*" >&2
  exit 1
}

cd "$APP_DIR"
load_env

finish() {
  status=$?
  trap - EXIT
  if [ "$status" -ne 0 ]; then
    notify_failure "$status" "Mattermost health check failed"
  fi
  exit "$status"
}
trap finish EXIT

disk_pct=$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
[ "$disk_pct" -lt 85 ] || fail "root disk usage ${disk_pct}% >= 85%"

mem_available_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
[ "$mem_available_kb" -gt 524288 ] || fail "available memory below 512MiB"

for svc in postgres mattermost-prod mattermost-test caddy; do
  id=$(compose ps -q "$svc")
  [ -n "$id" ] || fail "$svc container missing"
  state=$(docker inspect -f '{{.State.Status}}' "$id")
  [ "$state" = "running" ] || fail "$svc is $state"
done

prod_public=$(curl -L -s -o /dev/null -w '%{http_code}' --max-time 20 "https://${PROD_HOSTNAME}/" || true)
[ "$prod_public" = "200" ] || fail "production public endpoint returned $prod_public"

prod_internal=$(compose exec -T mattermost-prod curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/ || true)
[ "$prod_internal" = "200" ] || fail "production internal endpoint returned $prod_internal"

test_internal=$(compose exec -T mattermost-test curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/ || true)
[ "$test_internal" = "200" ] || fail "test internal endpoint returned $test_internal"

echo "$LOG_PREFIX OK disk=${disk_pct}% mem_available_kb=${mem_available_kb} prod_public=${prod_public} prod_internal=${prod_internal} test_internal=${test_internal}"
