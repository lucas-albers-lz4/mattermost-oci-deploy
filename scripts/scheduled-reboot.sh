#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[mattermost-reboot]"

if [ ! -f /var/run/reboot-required ]; then
  echo "$LOG_PREFIX no reboot required"
  exit 0
fi

echo "$LOG_PREFIX reboot required; scheduling restart"
logger -t mattermost-reboot "$LOG_PREFIX reboot required; initiating scheduled restart"
/sbin/shutdown -r now "Mattermost scheduled security reboot"
