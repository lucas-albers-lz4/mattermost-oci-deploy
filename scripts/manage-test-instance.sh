#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

TEST_PROFILE=upgrade-test
TEST_SERVICE=mattermost-test

usage() {
  cat <<EOF
Usage: $0 {start|stop|status}

Manage the upgrade-test Mattermost instance (Compose profile: $TEST_PROFILE).

  start   Start mattermost-test for upgrade validation
  stop    Stop mattermost-test to free RAM and CPU during normal operation
  status  Print whether the test container is absent, stopped, or running
EOF
}

test_container_id() {
  compose --profile "$TEST_PROFILE" ps -q "$TEST_SERVICE" 2>/dev/null || true
}

wait_for_test_internal() {
  attempts=${1:-30}
  i=1
  while [ "$i" -le "$attempts" ]; do
    code=$(compose exec -T "$TEST_SERVICE" curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/ 2>/dev/null || true)
    if [ "$code" = "200" ]; then
      return 0
    fi
    sleep 2
    i=$((i + 1))
  done
  return 1
}

cmd_start() {
  cd "$APP_DIR"
  load_env
  compose --profile "$TEST_PROFILE" up -d "$TEST_SERVICE"
  if ! wait_for_test_internal; then
    die "mattermost-test did not respond with HTTP 200 on internal health check"
  fi
  echo "mattermost-test started and internal HTTP check passed"
}

cmd_stop() {
  cd "$APP_DIR"
  load_env
  id=$(test_container_id)
  if [ -z "$id" ]; then
    echo "mattermost-test not present (profile inactive)"
    return 0
  fi
  state=$(docker inspect -f '{{.State.Status}}' "$id")
  if [ "$state" = "running" ]; then
    compose --profile "$TEST_PROFILE" stop "$TEST_SERVICE" >/dev/null
    echo "mattermost-test stopped"
  else
    echo "mattermost-test already $state"
  fi
}

cmd_status() {
  cd "$APP_DIR"
  load_env
  id=$(test_container_id)
  if [ -z "$id" ]; then
    echo "mattermost-test: absent"
    return 0
  fi
  state=$(docker inspect -f '{{.State.Status}}' "$id")
  echo "mattermost-test: $state"
}

case "${1:-}" in
  start)
    cmd_start
    ;;
  stop)
    cmd_stop
    ;;
  status)
    cmd_status
    ;;
  -h|--help|"")
    usage
    exit 0
    ;;
  *)
    echo "Unknown command: $1" >&2
    usage
    exit 64
    ;;
esac
