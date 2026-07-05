#!/usr/bin/env bash
# Configure Mattermost HPNS and mobile notification defaults for community users.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

PUSH_SERVER=${MM_PUSH_NOTIFICATION_SERVER:-https://global.push.mattermost.com}
SERVER_ONLY=false
USERS_ONLY=false
TARGET_USER=""

usage() {
  cat <<'EOF'
Usage:
  configure-push-notifications.sh
  configure-push-notifications.sh --server-only
  configure-push-notifications.sh --users-only
  configure-push-notifications.sh --user USERNAME

Sets production HPNS (global.push.mattermost.com by default) and updates human
users to mobile push "all" (not mentions-only). Idempotent.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --server-only) SERVER_ONLY=true; shift ;;
    --users-only) USERS_ONLY=true; shift ;;
    --user) TARGET_USER=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

require_command docker

cd "$APP_DIR"
load_env

mmctl_cfg() {
  compose exec -T -u mattermost mattermost-prod /mattermost/bin/mmctl --local config get "$1" 2>/dev/null | tr -d '\r'
}

configure_server() {
  current_send=$(mmctl_cfg EmailSettings.SendPushNotifications)
  if [ "$current_send" != "true" ]; then
    compose exec -T -u mattermost mattermost-prod \
      /mattermost/bin/mmctl --local config set EmailSettings.SendPushNotifications true
    echo "[push-config] enabled SendPushNotifications"
  else
    echo "[push-config] SendPushNotifications already true"
  fi

  current_server=$(mmctl_cfg EmailSettings.PushNotificationServer | tr -d '"')
  if [ "$current_server" != "$PUSH_SERVER" ]; then
    compose exec -T -u mattermost mattermost-prod \
      /mattermost/bin/mmctl --local config set EmailSettings.PushNotificationServer "$PUSH_SERVER"
    echo "[push-config] set PushNotificationServer=$PUSH_SERVER (was $current_server)"
  else
    echo "[push-config] PushNotificationServer already $PUSH_SERVER"
  fi
}

configure_users() {
  user_clause=""
  if [ -n "$TARGET_USER" ]; then
    validate_username "$TARGET_USER"
    user_clause="AND u.username = '$TARGET_USER'"
  fi

  updated=$(compose exec -T postgres psql -U postgres -d mattermost_prod -t -A -c "
    WITH targets AS (
      SELECT u.id, u.username
      FROM users u
      WHERE u.deleteat = 0
        AND u.username <> 'calls'
        AND NOT EXISTS (SELECT 1 FROM bots b WHERE b.userid = u.id)
        AND (u.notifyprops->>'push' IS DISTINCT FROM 'all'
             OR u.notifyprops->>'push_status' IS DISTINCT FROM 'online')
        $user_clause
    ),
    changed AS (
      UPDATE users u
      SET notifyprops = u.notifyprops || '{\"push\": \"all\", \"push_status\": \"online\"}'::jsonb
      FROM targets t
      WHERE u.id = t.id
      RETURNING u.username
    )
    SELECT COUNT(*) FROM changed;
  ")

  echo "[push-config] updated $updated user(s) to push=all push_status=online"
  if [ -n "$TARGET_USER" ] && [ "${updated:-0}" = "0" ]; then
    echo "[push-config] user $TARGET_USER already configured or not found"
  fi
}

validate_username() {
  local name=$1
  case "$name" in
    *[!a-z0-9._-]*|'') die "invalid username: $name" ;;
  esac
}

if [ "$USERS_ONLY" = true ]; then
  configure_users
elif [ "$SERVER_ONLY" = true ]; then
  configure_server
else
  configure_server
  configure_users
fi
