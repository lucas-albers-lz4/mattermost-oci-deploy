#!/usr/bin/env bash
# Collect push-notification diagnostics for Mattermost mobile delivery issues.
# Writes NDJSON debug entries when DEBUG_LOG_PATH is set (local debug workflow).
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

DEBUG_LOG_PATH=${DEBUG_LOG_PATH:-}
RUN_ID=${RUN_ID:-pre-fix}
SESSION_ID=${DEBUG_SESSION_ID:-666789}
REMOTE_HOST=${REMOTE_HOST:-}
REMOTE_USER=${REMOTE_USER:-ubuntu}

log_debug() {
  hypothesis_id=$1
  location=$2
  message=$3
  data_json=$4

  if [ -z "$DEBUG_LOG_PATH" ]; then
    return 0
  fi

  ts=$(date +%s000)
  payload=$(printf '{"sessionId":"%s","runId":"%s","hypothesisId":"%s","location":"%s","message":"%s","data":%s,"timestamp":%s}' \
    "$SESSION_ID" "$RUN_ID" "$hypothesis_id" "$location" "$message" "$data_json" "$ts")

  # #region agent log
  printf '%s\n' "$payload" >>"$DEBUG_LOG_PATH"
  # #endregion
}

run_remote() {
  if [ -n "$REMOTE_HOST" ]; then
    ssh -o BatchMode=yes -o ConnectTimeout=15 "$REMOTE_USER@$REMOTE_HOST" "$@"
  else
    bash -lc "$*"
  fi
}

mmctl_get() {
  key=$1
  run_remote "cd '$APP_DIR' && docker compose --env-file .env -p mattermost exec -T -u mattermost mattermost-prod /mattermost/bin/mmctl --local config get '$key' 2>/dev/null | tr -d '\r'"
}

psql_query() {
  sql=$1
  run_remote "cd '$APP_DIR' && docker compose --env-file .env -p mattermost exec -T postgres psql -U postgres -d mattermost_prod -t -A -c \"$sql\" 2>/dev/null"
}

APP_DIR=${APP_DIR:-/opt/mattermost}

require_command python3
if [ -n "$REMOTE_HOST" ]; then
  require_command ssh
else
  require_command docker
  cd "$APP_DIR"
  load_env
fi

send_push=$(mmctl_get EmailSettings.SendPushNotifications)
push_server=$(mmctl_get EmailSettings.PushNotificationServer | tr -d '"')
site_url=$(mmctl_get ServiceSettings.SiteURL | tr -d '"')

# #region agent log
log_debug "A" "diagnose-push-notifications.sh:config" "push server config" \
  "{\"sendPush\":$(printf '%s' "$send_push" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'),\"pushServer\":$(printf '%s' "$push_server" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'),\"siteUrl\":$(printf '%s' "$site_url" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')}"
# #endregion

push_test_http=$(run_remote "cd '$APP_DIR' && docker compose --env-file .env -p mattermost exec -T mattermost-prod curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://push-test.mattermost.com/ 2>/dev/null || echo fail")
push_test_https=$(run_remote "cd '$APP_DIR' && docker compose --env-file .env -p mattermost exec -T mattermost-prod curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://push-test.mattermost.com/ 2>/dev/null || echo fail")
global_https=$(run_remote "cd '$APP_DIR' && docker compose --env-file .env -p mattermost exec -T mattermost-prod curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://global.push.mattermost.com/ 2>/dev/null || echo fail")

# #region agent log
log_debug "B" "diagnose-push-notifications.sh:connectivity" "push proxy reachability from container" \
  "{\"pushTestHttp\":$(printf '%s' "$push_test_http" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'),\"pushTestHttps\":$(printf '%s' "$push_test_https" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'),\"globalHttps\":$(printf '%s' "$global_https" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')}"
# #endregion

android_devices=$(psql_query "SELECT COUNT(*) FROM sessions WHERE deviceid LIKE 'android%';")
ios_devices=$(psql_query "SELECT COUNT(*) FROM sessions WHERE deviceid LIKE 'apple%' OR deviceid LIKE 'ios%';")
total_mobile=$(psql_query "SELECT COUNT(*) FROM sessions WHERE deviceid IS NOT NULL AND deviceid != '';")

# #region agent log
log_debug "C" "diagnose-push-notifications.sh:devices" "registered mobile device sessions" \
  "{\"androidDevices\":${android_devices:-0},\"iosDevices\":${ios_devices:-0},\"totalMobile\":${total_mobile:-0}}"
# #endregion

user_notify_json=$(psql_query "SELECT COALESCE(json_agg(json_build_object('username', username, 'push', notifyprops->>'push', 'push_status', notifyprops->>'push_status')), '[]'::json)::text FROM users WHERE deleteat=0 AND username NOT LIKE '%bot%' AND username != 'calls';")

# #region agent log
log_debug "D" "diagnose-push-notifications.sh:notifyprops" "user push notification preferences" "$user_notify_json"
# #endregion

recent_push_logs=$(run_remote "cd '$APP_DIR' && docker compose --env-file .env -p mattermost logs mattermost-prod --since=48h 2>&1 | grep -iE 'push_proxy|notification_push|Push notification server' | tail -10 | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'")

# #region agent log
log_debug "E" "diagnose-push-notifications.sh:logs" "recent push-related server logs" "{\"lines\":$recent_push_logs}"
# #endregion

echo "[push-diagnose] sendPush=$send_push pushServer=$push_server"
echo "[push-diagnose] devices android=$android_devices ios=$ios_devices total=$total_mobile"
echo "[push-diagnose] connectivity push-test(http=$push_test_http https=$push_test_https) global=$global_https"
echo "[push-diagnose] user notify props: $user_notify_json"
if [ -n "$DEBUG_LOG_PATH" ]; then
  echo "[push-diagnose] wrote debug entries to $DEBUG_LOG_PATH"
fi
