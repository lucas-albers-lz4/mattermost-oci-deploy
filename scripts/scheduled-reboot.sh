#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

LOG_PREFIX="[mattermost-reboot]"

APP_DIR=${APP_DIR:-/opt/mattermost}
if [ -f "${APP_DIR}/.env" ]; then
  # shellcheck disable=SC1091
  source "${APP_DIR}/.env"
fi

if [ ! -f /var/run/reboot-required ]; then
  echo "$LOG_PREFIX no reboot required"
  notify_maintenance "Scheduled reboot skipped (not required)"
  exit 0
fi

reboot_pkg=$(tr '\n' ' ' </var/run/reboot-required.pkgs 2>/dev/null || cat /var/run/reboot-required 2>/dev/null || true)
echo "$LOG_PREFIX reboot required; scheduling restart (${reboot_pkg:-kernel update})"
notify_maintenance "Scheduled reboot initiating (${reboot_pkg:-kernel update pending})"
logger -t mattermost-reboot "$LOG_PREFIX reboot required; initiating scheduled restart"
/sbin/shutdown -r now "Mattermost scheduled security reboot"
