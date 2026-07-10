#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

LOG_PREFIX="[mattermost-post-maintenance]"

cd "$APP_DIR"
load_env

parts=()

if [ -f /var/run/reboot-required ]; then
  reboot_pkg=$(tr '\n' ' ' </var/run/reboot-required.pkgs 2>/dev/null || cat /var/run/reboot-required 2>/dev/null || true)
  parts+=("reboot still required (${reboot_pkg:-pending})")
else
  parts+=("reboot-required cleared")
fi

if systemctl is-enabled mattermost-caddy-update.timer &>/dev/null; then
  caddy_result=$(systemctl show mattermost-caddy-update.service -p Result --value 2>/dev/null || echo unknown)
  caddy_time=$(systemctl show mattermost-caddy-update.service -p ExecMainStartTimestamp --value 2>/dev/null || echo never)
  parts+=("Caddy last run ${caddy_time} result=${caddy_result}")
else
  parts+=("Caddy timer not installed")
fi

if systemctl is-enabled mattermost-reboot.timer &>/dev/null; then
  reboot_result=$(systemctl show mattermost-reboot.service -p Result --value 2>/dev/null || echo unknown)
  reboot_time=$(systemctl show mattermost-reboot.service -p ExecMainStartTimestamp --value 2>/dev/null || echo never)
  parts+=("Reboot timer last run ${reboot_time} result=${reboot_result}")
else
  parts+=("Reboot timer not installed")
fi

set +e
health_summary=$("$SCRIPT_DIR/health-check.sh" 2>&1 | tail -1)
health_status=$?
set -e
if [ "$health_status" -ne 0 ] || [ -z "$health_summary" ]; then
  health_summary="health check failed (exit ${health_status})"
fi
parts+=("$health_summary")

summary=$(IFS='; '; echo "${parts[*]}")
echo "$LOG_PREFIX ${summary}"
notify_maintenance "Post-maintenance summary: ${summary}"
echo "$LOG_PREFIX done"
